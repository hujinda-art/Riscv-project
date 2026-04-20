`timescale 1ns / 1ps
//
// 协议转换：I$ / inst_mem 侧「req/addr/rdata/ready」 -> AXI4 读主端口（单 outstanding、单拍 AR）。
// 用于 Vivado BD：本模块 M_AXI_* 接到 AXI SmartConnect 某一从口（Slave Interface）。
//
// 约定：mem_addr 字对齐；mem_req 在事务完成前应保持为 1（与当前 L1 refill 行为一致）。
//
module axi_if_imem_master #(
    parameter integer C_AXI_ADDR_WIDTH = 32,
    parameter integer C_AXI_DATA_WIDTH = 32,
    parameter integer C_AXI_ID_WIDTH   = 4
) (
    input wire clk,
    input wire rst_n,

    // 本地类 SRAM 读口（接 L1_Cache_INST 的 mem_*）
    input  wire                     mem_req,
    input  wire [C_AXI_ADDR_WIDTH-1:0] mem_addr,
    output reg  [C_AXI_DATA_WIDTH-1:0] mem_rdata,
    output reg                      mem_ready,

    // AXI4 Read Address
    output reg  [C_AXI_ID_WIDTH-1:0]   m_axi_arid,
    output reg  [C_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]                  m_axi_arlen,
    output reg  [2:0]                  m_axi_arsize,
    output reg  [1:0]                  m_axi_arburst,
    output reg  [2:0]                  m_axi_arprot,
    output reg                         m_axi_arvalid,
    input  wire                        m_axi_arready,
    // AXI4 Read Data
    input  wire [C_AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  wire [C_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]                  m_axi_rresp,
    input  wire                        m_axi_rlast,
    input  wire                        m_axi_rvalid,
    output reg                         m_axi_rready
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_AR   = 2'd1;
    localparam [1:0] S_R   = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            m_axi_arid   <= {C_AXI_ID_WIDTH{1'b0}};
            m_axi_araddr <= {C_AXI_ADDR_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd2; // 4 bytes
            m_axi_arburst <= 2'b01; // INCR
            m_axi_arprot  <= 3'b000;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            mem_rdata     <= {C_AXI_DATA_WIDTH{1'b0}};
            mem_ready     <= 1'b0;
        end else begin
            mem_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (mem_req) begin
                        m_axi_arid    <= {C_AXI_ID_WIDTH{1'b0}};
                        m_axi_araddr  <= {mem_addr[C_AXI_ADDR_WIDTH-1:2], 2'b00};
                        m_axi_arlen   <= 8'd0;
                        m_axi_arsize  <= 3'd2;
                        m_axi_arburst <= 2'b01;
                        m_axi_arprot  <= 3'b000;
                        m_axi_arvalid <= 1'b1;
                        m_axi_rready  <= 1'b0;
                        state         <= S_AR;
                    end
                end

                S_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_R;
                    end
                end

                S_R: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid && m_axi_rready) begin
                        mem_rdata     <= m_axi_rdata;
                        mem_ready     <= 1'b1;
                        m_axi_rready  <= 1'b0;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
