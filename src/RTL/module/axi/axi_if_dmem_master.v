`timescale 1ns / 1ps
//
// 协议转换：data_mem 侧「valid/ren/wen/size/addr/wdata/rdata/ready」-> AXI4 读写主端口。
// 单 outstanding：一次只处理一个读或写；与 hazard_ctrl 通过 dmem_ready 反压配合。
//
// 当前工程 core_top 将 dmem_size 固定为字传输（SOC_MEM_SIZE_WORD），此处按全字实现。
// 若以后放开 SB/SH，请扩展 wstrb/arsize 及读返回掩码。
//
module axi_if_dmem_master #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 32,
    parameter integer C_AXI_ID_WIDTH   = 4
) (
    input wire clk,
    input wire rst_n,

    input  wire                     dmem_valid,
    input  wire                     dmem_ren,
    input  wire                     dmem_wen,
    input  wire [1:0]               dmem_size,
    input  wire [C_AXI_ADDR_WIDTH-1:0] dmem_addr,
    input  wire [C_AXI_DATA_WIDTH-1:0] dmem_wdata,
    output reg  [C_AXI_DATA_WIDTH-1:0] dmem_rdata,
    output reg                      dmem_ready,

    // Write address
    output reg  [C_AXI_ID_WIDTH-1:0]   m_axi_awid,
    output reg  [C_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [7:0]                  m_axi_awlen,
    output reg  [2:0]                  m_axi_awsize,
    output reg  [1:0]                  m_axi_awburst,
    output reg  [2:0]                  m_axi_awprot,
    output reg                         m_axi_awvalid,
    input  wire                        m_axi_awready,
    // Write data
    output reg  [C_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [(C_AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output reg                         m_axi_wlast,
    output reg                         m_axi_wvalid,
    input  wire                        m_axi_wready,
    // Write response
    input  wire [C_AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]                  m_axi_bresp,
    input  wire                        m_axi_bvalid,
    output reg                         m_axi_bready,
    // Read address
    output reg  [C_AXI_ID_WIDTH-1:0]   m_axi_arid,
    output reg  [C_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]                  m_axi_arlen,
    output reg  [2:0]                  m_axi_arsize,
    output reg  [1:0]                  m_axi_arburst,
    output reg  [2:0]                  m_axi_arprot,
    output reg                         m_axi_arvalid,
    input  wire                        m_axi_arready,
    // Read data
    input  wire [C_AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  wire [C_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]                  m_axi_rresp,
    input  wire                        m_axi_rlast,
    input  wire                        m_axi_rvalid,
    output reg                         m_axi_rready
);

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_R_AR  = 3'd1;
    localparam [2:0] S_R_R   = 3'd2;
    localparam [2:0] S_W_AW  = 3'd3;
    localparam [2:0] S_W_W   = 3'd4;
    localparam [2:0] S_W_B   = 3'd5;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            m_axi_awid    <= {C_AXI_ID_WIDTH{1'b0}};
            m_axi_awaddr  <= {C_AXI_ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'd2;
            m_axi_awburst <= 2'b01;
            m_axi_awprot  <= 3'b000;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= {C_AXI_DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= {(C_AXI_DATA_WIDTH/8){1'b0}};
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_arid    <= {C_AXI_ID_WIDTH{1'b0}};
            m_axi_araddr  <= {C_AXI_ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd2;
            m_axi_arburst <= 2'b01;
            m_axi_arprot  <= 3'b000;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            dmem_rdata    <= {C_AXI_DATA_WIDTH{1'b0}};
            dmem_ready    <= 1'b0;
        end else begin
            dmem_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;

                    if (dmem_valid && dmem_ren) begin
                        m_axi_arid    <= {C_AXI_ID_WIDTH{1'b0}};
                        m_axi_araddr  <= {dmem_addr[C_AXI_ADDR_WIDTH-1:2], 2'b00};
                        m_axi_arlen   <= 8'd0;
                        m_axi_arburst <= 2'b01;
                        m_axi_arprot  <= 3'b000;
                        m_axi_arvalid <= 1'b1;
                        case (dmem_size)
                            2'b10:   m_axi_arsize <= 3'd2;
                            default: m_axi_arsize <= 3'd2;
                        endcase
                        state         <= S_R_AR;
                    end else if (dmem_valid && dmem_wen) begin
                        m_axi_awid    <= {C_AXI_ID_WIDTH{1'b0}};
                        m_axi_awaddr  <= {dmem_addr[C_AXI_ADDR_WIDTH-1:2], 2'b00};
                        m_axi_awlen   <= 8'd0;
                        m_axi_awburst <= 2'b01;
                        m_axi_awprot  <= 3'b000;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wdata   <= dmem_wdata;
                        m_axi_wlast   <= 1'b1;
                        m_axi_wvalid  <= 1'b0;
                        case (dmem_size)
                            2'b10: begin
                                m_axi_awsize <= 3'd2;
                                m_axi_wstrb  <= 4'b1111;
                            end
                            default: begin
                                // 与当前 core 固定字宽一致；扩展 SB/SH 时在此补 wstrb/awsize
                                m_axi_awsize <= 3'd2;
                                m_axi_wstrb  <= 4'b1111;
                            end
                        endcase
                        state         <= S_W_AW;
                    end
                end

                S_R_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_R_R;
                    end
                end

                S_R_R: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid && m_axi_rready) begin
                        dmem_rdata     <= m_axi_rdata;
                        dmem_ready     <= 1'b1;
                        m_axi_rready   <= 1'b0;
                        state          <= S_IDLE;
                    end
                end

                S_W_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        state         <= S_W_W;
                    end
                end

                S_W_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_W_B;
                    end
                end

                S_W_B: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready) begin
                        dmem_ready   <= 1'b1;
                        m_axi_bready <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
