`timescale 1ns / 1ps
//
// fpga_top — AXI + Cache 路径
// 使用 soc_top (含 L1_Cache_INST) + Vivado BD soc_wrapper
//
// 上板前请将以下源文件加入 Vivado 工程：
//   src/RTL/core/soc_top.v
//   src/RTL/core/core_top.v 及所有子模块
//   src/RTL/module/Cache/L1_Cache_INST.v, LFSR16_inst.v
//   src/RTL/module/axi/axi_if_imem_master.v, axi_if_dmem_master.v
//   src/bd/soc/hdl/soc_wrapper.v 及 generate 出的 soc.v
//

`include "soc_top.v"

module fpga_top (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led
);

    // soc_wrapper 无 AXI ID 端口时，rid/bid 由常数驱动回 soc_top
    wire [3:0] w_imem_rid_in  = 4'b0;
    wire [3:0] w_dmem_rid_in  = 4'b0;
    wire [3:0] w_dmem_bid_in  = 4'b0;

    // Basys3 BTNU (V17) 按下为高电平；SoC/BD 的 rst_n 均为低有效，需反相
    wire sys_rst_n = ~rst_n;

    wire [3:0] axi_arcache_d = 4'b0011;
    wire [3:0] axi_awcache_d = 4'b0011;
    wire [3:0] axi_arqos_d   = 4'b0;
    wire [3:0] axi_awqos_d   = 4'b0;
    wire [0:0] axi_arlock_d  = 1'b0;
    wire [0:0] axi_awlock_d  = 1'b0;

    wire [31:0] id_pc_w;
    wire [31:0] id_pc_plus4_w;
    wire [31:0] instr_out_w;
    wire        instr_valid_out_w;
    wire [6:0]  fun7_out_w;
    wire [4:0]  rs2_out_w;
    wire [4:0]  rs1_out_w;
    wire [2:0]  fuc3_out_w;
    wire [6:0]  opcode_out_w;
    wire [4:0]  rd_out_w;
    wire [31:0] ex_pc_out_w;
    wire [31:0] ex_pc_plus4_out_w;
    wire [31:0] ex_instr_out_w;
    wire        ex_instr_valid_out_w;
    wire [31:0] ex_imm_out_w;
    wire [31:0] ex_result_out_w;
    wire [31:0] ex_mem_addr_out_w;
    wire [31:0] ex_mem_wdata_out_w;

    // imem AXI（连 S00）
    wire [3:0]  w_imem_arid;
    wire [31:0] w_imem_araddr;
    wire [7:0]  w_imem_arlen;
    wire [2:0]  w_imem_arsize;
    wire [1:0]  w_imem_arburst;
    wire [2:0]  w_imem_arprot;
    wire        w_imem_arvalid;
    wire        w_imem_arready;
    wire [31:0] w_imem_rdata;
    wire [1:0]  w_imem_rresp;
    wire        w_imem_rlast;
    wire        w_imem_rvalid;
    wire        w_imem_rready;

    // dmem AXI（连 S01）
    wire [3:0]  w_dmem_awid;
    wire [31:0] w_dmem_awaddr;
    wire [7:0]  w_dmem_awlen;
    wire [2:0]  w_dmem_awsize;
    wire [1:0]  w_dmem_awburst;
    wire [2:0]  w_dmem_awprot;
    wire        w_dmem_awvalid;
    wire        w_dmem_awready;
    wire [31:0] w_dmem_wdata;
    wire [3:0]  w_dmem_wstrb;
    wire        w_dmem_wlast;
    wire        w_dmem_wvalid;
    wire        w_dmem_wready;
    wire [1:0]  w_dmem_bresp;
    wire        w_dmem_bvalid;
    wire        w_dmem_bready;
    wire [3:0]  w_dmem_arid;
    wire [31:0] w_dmem_araddr;
    wire [7:0]  w_dmem_arlen;
    wire [2:0]  w_dmem_arsize;
    wire [1:0]  w_dmem_arburst;
    wire [2:0]  w_dmem_arprot;
    wire        w_dmem_arvalid;
    wire        w_dmem_arready;
    wire [31:0] w_dmem_rdata;
    wire [1:0]  w_dmem_rresp;
    wire        w_dmem_rlast;
    wire        w_dmem_rvalid;
    wire        w_dmem_rready;

    (* dont_touch = "yes" *)
    soc_top u_soc (
        .clk                 (clk),
        .rst_n               (sys_rst_n),
        .stall               (1'b0),
        .flush               (1'b0),
        .exception           (1'b0),
        .pc_exception        (32'b0),
        .interrupt           (1'b0),
        .pc_interrupt        (32'b0),
        .id_pc               (id_pc_w),
        .id_pc_plus4         (id_pc_plus4_w),
        .instr_out           (instr_out_w),
        .instr_valid_out     (instr_valid_out_w),
        .fun7_out            (fun7_out_w),
        .rs2_out             (rs2_out_w),
        .rs1_out             (rs1_out_w),
        .fuc3_out            (fuc3_out_w),
        .opcode_out          (opcode_out_w),
        .rd_out              (rd_out_w),
        .ex_pc_out           (ex_pc_out_w),
        .ex_pc_plus4_out     (ex_pc_plus4_out_w),
        .ex_instr_out        (ex_instr_out_w),
        .ex_instr_valid_out  (ex_instr_valid_out_w),
        .ex_imm_out          (ex_imm_out_w),
        .ex_result_out       (ex_result_out_w),
        .ex_mem_addr_out     (ex_mem_addr_out_w),
        .ex_mem_wdata_out    (ex_mem_wdata_out_w),
        .m_axi_imem_arid     (w_imem_arid),
        .m_axi_imem_araddr   (w_imem_araddr),
        .m_axi_imem_arlen    (w_imem_arlen),
        .m_axi_imem_arsize   (w_imem_arsize),
        .m_axi_imem_arburst  (w_imem_arburst),
        .m_axi_imem_arprot   (w_imem_arprot),
        .m_axi_imem_arvalid  (w_imem_arvalid),
        .m_axi_imem_arready  (w_imem_arready),
        .m_axi_imem_rid      (w_imem_rid_in),
        .m_axi_imem_rdata    (w_imem_rdata),
        .m_axi_imem_rresp    (w_imem_rresp),
        .m_axi_imem_rlast    (w_imem_rlast),
        .m_axi_imem_rvalid   (w_imem_rvalid),
        .m_axi_imem_rready   (w_imem_rready),
        .m_axi_dmem_awid     (w_dmem_awid),
        .m_axi_dmem_awaddr   (w_dmem_awaddr),
        .m_axi_dmem_awlen    (w_dmem_awlen),
        .m_axi_dmem_awsize   (w_dmem_awsize),
        .m_axi_dmem_awburst  (w_dmem_awburst),
        .m_axi_dmem_awprot   (w_dmem_awprot),
        .m_axi_dmem_awvalid  (w_dmem_awvalid),
        .m_axi_dmem_awready  (w_dmem_awready),
        .m_axi_dmem_wdata    (w_dmem_wdata),
        .m_axi_dmem_wstrb    (w_dmem_wstrb),
        .m_axi_dmem_wlast    (w_dmem_wlast),
        .m_axi_dmem_wvalid   (w_dmem_wvalid),
        .m_axi_dmem_wready   (w_dmem_wready),
        .m_axi_dmem_bid      (w_dmem_bid_in),
        .m_axi_dmem_bresp    (w_dmem_bresp),
        .m_axi_dmem_bvalid   (w_dmem_bvalid),
        .m_axi_dmem_bready   (w_dmem_bready),
        .m_axi_dmem_arid     (w_dmem_arid),
        .m_axi_dmem_araddr   (w_dmem_araddr),
        .m_axi_dmem_arlen    (w_dmem_arlen),
        .m_axi_dmem_arsize   (w_dmem_arsize),
        .m_axi_dmem_arburst  (w_dmem_arburst),
        .m_axi_dmem_arprot   (w_dmem_arprot),
        .m_axi_dmem_arvalid  (w_dmem_arvalid),
        .m_axi_dmem_arready  (w_dmem_arready),
        .m_axi_dmem_rid      (w_dmem_rid_in),
        .m_axi_dmem_rdata    (w_dmem_rdata),
        .m_axi_dmem_rresp    (w_dmem_rresp),
        .m_axi_dmem_rlast    (w_dmem_rlast),
        .m_axi_dmem_rvalid   (w_dmem_rvalid),
        .m_axi_dmem_rready   (w_dmem_rready)
    );

    // BD：指令口 -> S00_AXI_0；数据口 -> S01_AXI_0。imem 仅读，S00 写通道接空闲。
    wire        s00_nc_awready;
    wire [1:0]  s00_nc_bresp;
    wire        s00_nc_bvalid;
    wire        s00_nc_wready;

    soc_wrapper u_soc_bd (
        .S00_AXI_0_araddr  (w_imem_araddr),
        .S00_AXI_0_arburst (w_imem_arburst),
        .S00_AXI_0_arcache (axi_arcache_d),
        .S00_AXI_0_arlen   (w_imem_arlen),
        .S00_AXI_0_arlock  (axi_arlock_d),
        .S00_AXI_0_arprot  (w_imem_arprot),
        .S00_AXI_0_arqos   (axi_arqos_d),
        .S00_AXI_0_arready (w_imem_arready),
        .S00_AXI_0_arsize  (w_imem_arsize),
        .S00_AXI_0_arvalid (w_imem_arvalid),
        .S00_AXI_0_awaddr  (32'b0),
        .S00_AXI_0_awburst (2'b0),
        .S00_AXI_0_awcache (4'b0),
        .S00_AXI_0_awlen   (8'b0),
        .S00_AXI_0_awlock  (1'b0),
        .S00_AXI_0_awprot  (3'b0),
        .S00_AXI_0_awqos   (4'b0),
        .S00_AXI_0_awready (s00_nc_awready),
        .S00_AXI_0_awsize  (3'b0),
        .S00_AXI_0_awvalid (1'b0),
        .S00_AXI_0_bready  (1'b1),
        .S00_AXI_0_bresp   (s00_nc_bresp),
        .S00_AXI_0_bvalid  (s00_nc_bvalid),
        .S00_AXI_0_rdata   (w_imem_rdata),
        .S00_AXI_0_rlast   (w_imem_rlast),
        .S00_AXI_0_rready  (w_imem_rready),
        .S00_AXI_0_rresp   (w_imem_rresp),
        .S00_AXI_0_rvalid  (w_imem_rvalid),
        .S00_AXI_0_wdata   (32'b0),
        .S00_AXI_0_wlast   (1'b0),
        .S00_AXI_0_wready  (s00_nc_wready),
        .S00_AXI_0_wstrb   (4'b0),
        .S00_AXI_0_wvalid  (1'b0),

        .S01_AXI_0_araddr  (w_dmem_araddr),
        .S01_AXI_0_arburst (w_dmem_arburst),
        .S01_AXI_0_arcache (axi_arcache_d),
        .S01_AXI_0_arlen   (w_dmem_arlen),
        .S01_AXI_0_arlock  (axi_arlock_d),
        .S01_AXI_0_arprot  (w_dmem_arprot),
        .S01_AXI_0_arqos   (axi_arqos_d),
        .S01_AXI_0_arready (w_dmem_arready),
        .S01_AXI_0_arsize  (w_dmem_arsize),
        .S01_AXI_0_arvalid (w_dmem_arvalid),
        .S01_AXI_0_awaddr  (w_dmem_awaddr),
        .S01_AXI_0_awburst (w_dmem_awburst),
        .S01_AXI_0_awcache (axi_awcache_d),
        .S01_AXI_0_awlen   (w_dmem_awlen),
        .S01_AXI_0_awlock  (axi_awlock_d),
        .S01_AXI_0_awprot  (w_dmem_awprot),
        .S01_AXI_0_awqos   (axi_awqos_d),
        .S01_AXI_0_awready (w_dmem_awready),
        .S01_AXI_0_awsize  (w_dmem_awsize),
        .S01_AXI_0_awvalid (w_dmem_awvalid),
        .S01_AXI_0_bready  (w_dmem_bready),
        .S01_AXI_0_bresp   (w_dmem_bresp),
        .S01_AXI_0_bvalid  (w_dmem_bvalid),
        .S01_AXI_0_rdata   (w_dmem_rdata),
        .S01_AXI_0_rlast   (w_dmem_rlast),
        .S01_AXI_0_rready  (w_dmem_rready),
        .S01_AXI_0_rresp   (w_dmem_rresp),
        .S01_AXI_0_rvalid  (w_dmem_rvalid),
        .S01_AXI_0_wdata   (w_dmem_wdata),
        .S01_AXI_0_wlast   (w_dmem_wlast),
        .S01_AXI_0_wready  (w_dmem_wready),
        .S01_AXI_0_wstrb   (w_dmem_wstrb),
        .S01_AXI_0_wvalid  (w_dmem_wvalid),

        .clk_in1_0         (clk),
        .ext_reset_in_0    (sys_rst_n),
        .reset_0           (sys_rst_n)
    );

    assign led = ex_result_out_w[7:0];

endmodule
