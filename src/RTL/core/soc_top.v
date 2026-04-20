`timescale 1ns / 1ps
`include "../include/soc_config.vh"
`include "../include/soc_addr_map.vh"
//
// SoC 顶层：CPU + L1 I$ + AXI 主端口（指令只读、数据读写）。
// 片内 inst_mem / data_mem 已移除；存储由 BD 侧 AXI SmartConnect + BRAM/DDR 提供。
//
`include "core_top.v"
`include "../module/Cache/L1_Cache_INST.v"
`include "../module/axi/axi_if_imem_master.v"
`include "../module/axi/axi_if_dmem_master.v"

module soc_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        stall,
    input  wire        flush,
    input  wire        exception,
    input  wire [31:0] pc_exception,
    input  wire        interrupt,
    input  wire [31:0] pc_interrupt,

    // 调试观测端口，与 core_top 保持一致
    output wire [31:0] id_pc,
    output wire [31:0] id_pc_plus4,
    output wire [31:0] instr_out,
    output wire        instr_valid_out,

    output wire [6:0]  fun7_out,
    output wire [4:0]  rs2_out,
    output wire [4:0]  rs1_out,
    output wire [2:0]  fuc3_out,
    output wire [6:0]  opcode_out,
    output wire [4:0]  rd_out,

    output wire [31:0] ex_pc_out,
    output wire [31:0] ex_pc_plus4_out,
    output wire [31:0] ex_instr_out,
    output wire        ex_instr_valid_out,
    output wire [31:0] ex_imm_out,

    output wire [31:0] ex_result_out,
    output wire [31:0] ex_mem_addr_out,
    output wire [31:0] ex_mem_wdata_out,

    // ---------- AXI4 Master：指令口（仅读 AR/R），接 SmartConnect S00 ----------
    output wire [3:0]  m_axi_imem_arid,
    output wire [31:0] m_axi_imem_araddr,
    output wire [7:0]  m_axi_imem_arlen,
    output wire [2:0]  m_axi_imem_arsize,
    output wire [1:0]  m_axi_imem_arburst,
    output wire [2:0]  m_axi_imem_arprot,
    output wire        m_axi_imem_arvalid,
    input  wire        m_axi_imem_arready,
    input  wire [3:0]  m_axi_imem_rid,
    input  wire [31:0] m_axi_imem_rdata,
    input  wire [1:0]  m_axi_imem_rresp,
    input  wire        m_axi_imem_rlast,
    input  wire        m_axi_imem_rvalid,
    output wire        m_axi_imem_rready,

    // ---------- AXI4 Master：数据口（AW/W/B + AR/R），接 SmartConnect S01 ----------
    output wire [3:0]  m_axi_dmem_awid,
    output wire [31:0] m_axi_dmem_awaddr,
    output wire [7:0]  m_axi_dmem_awlen,
    output wire [2:0]  m_axi_dmem_awsize,
    output wire [1:0]  m_axi_dmem_awburst,
    output wire [2:0]  m_axi_dmem_awprot,
    output wire        m_axi_dmem_awvalid,
    input  wire        m_axi_dmem_awready,
    output wire [31:0] m_axi_dmem_wdata,
    output wire [3:0]  m_axi_dmem_wstrb,
    output wire        m_axi_dmem_wlast,
    output wire        m_axi_dmem_wvalid,
    input  wire        m_axi_dmem_wready,
    input  wire [3:0]  m_axi_dmem_bid,
    input  wire [1:0]  m_axi_dmem_bresp,
    input  wire        m_axi_dmem_bvalid,
    output wire        m_axi_dmem_bready,
    output wire [3:0]  m_axi_dmem_arid,
    output wire [31:0] m_axi_dmem_araddr,
    output wire [7:0]  m_axi_dmem_arlen,
    output wire [2:0]  m_axi_dmem_arsize,
    output wire [1:0]  m_axi_dmem_arburst,
    output wire [2:0]  m_axi_dmem_arprot,
    output wire        m_axi_dmem_arvalid,
    input  wire        m_axi_dmem_arready,
    input  wire [3:0]  m_axi_dmem_rid,
    input  wire [31:0] m_axi_dmem_rdata,
    input  wire [1:0]  m_axi_dmem_rresp,
    input  wire        m_axi_dmem_rlast,
    input  wire        m_axi_dmem_rvalid,
    output wire        m_axi_dmem_rready
);

    // ---- 指令总线：core <-> L1 I$ <-> axi_if_imem ----
    wire [31:0] imem_addr;
    wire        imem_req;
    wire [31:0] imem_rdata;
    wire        imem_ready;
    wire [31:0] ic_mem_addr;
    wire        ic_mem_req;
    wire [31:0] ic_mem_rdata;
    wire        ic_mem_ready;

    // ---- 数据总线：core <-> axi_if_dmem ----
    wire        dmem_wen;
    wire        dmem_ren;
    wire        dmem_valid;
    wire [1:0]  dmem_size;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;

    core_top u_core (
        .clk               (clk),
        .rst_n             (rst_n),
        .stall             (stall),
        .flush             (flush),
        .exception         (exception),
        .pc_exception      (pc_exception),
        .interrupt         (interrupt),
        .pc_interrupt      (pc_interrupt),
        .id_pc             (id_pc),
        .id_pc_plus4       (id_pc_plus4),
        .instr_out         (instr_out),
        .instr_valid_out   (instr_valid_out),
        .fun7_out          (fun7_out),
        .rs2_out           (rs2_out),
        .rs1_out           (rs1_out),
        .fuc3_out          (fuc3_out),
        .opcode_out        (opcode_out),
        .rd_out            (rd_out),
        .ex_pc_out         (ex_pc_out),
        .ex_pc_plus4_out   (ex_pc_plus4_out),
        .ex_instr_out      (ex_instr_out),
        .ex_instr_valid_out(ex_instr_valid_out),
        .ex_imm_out        (ex_imm_out),
        .ex_result_out     (ex_result_out),
        .ex_mem_addr_out   (ex_mem_addr_out),
        .ex_mem_wdata_out  (ex_mem_wdata_out),
        .imem_addr         (imem_addr),
        .imem_req          (imem_req),
        .imem_rdata        (imem_rdata),
        .imem_ready        (imem_ready),
        .dmem_wen          (dmem_wen),
        .dmem_ren          (dmem_ren),
        .dmem_valid        (dmem_valid),
        .dmem_size         (dmem_size),
        .dmem_addr         (dmem_addr),
        .dmem_wdata        (dmem_wdata),
        .dmem_rdata        (dmem_rdata),
        .dmem_ready        (dmem_ready)
    );

    L1_Cache_INST u_icache (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_req   (imem_req),
        .imem_rdata (imem_rdata),
        .imem_ready (imem_ready),
        .mem_addr   (ic_mem_addr),
        .mem_req    (ic_mem_req),
        .mem_rdata  (ic_mem_rdata),
        .mem_ready  (ic_mem_ready)
    );

    axi_if_imem_master u_axi_imem (
        .clk           (clk),
        .rst_n         (rst_n),
        .mem_req       (ic_mem_req),
        .mem_addr      (ic_mem_addr),
        .mem_rdata     (ic_mem_rdata),
        .mem_ready     (ic_mem_ready),
        .m_axi_arid    (m_axi_imem_arid),
        .m_axi_araddr  (m_axi_imem_araddr),
        .m_axi_arlen   (m_axi_imem_arlen),
        .m_axi_arsize  (m_axi_imem_arsize),
        .m_axi_arburst (m_axi_imem_arburst),
        .m_axi_arprot  (m_axi_imem_arprot),
        .m_axi_arvalid (m_axi_imem_arvalid),
        .m_axi_arready (m_axi_imem_arready),
        .m_axi_rid     (m_axi_imem_rid),
        .m_axi_rdata   (m_axi_imem_rdata),
        .m_axi_rresp   (m_axi_imem_rresp),
        .m_axi_rlast   (m_axi_imem_rlast),
        .m_axi_rvalid  (m_axi_imem_rvalid),
        .m_axi_rready  (m_axi_imem_rready)
    );

    axi_if_dmem_master u_axi_dmem (
        .clk           (clk),
        .rst_n         (rst_n),
        .dmem_valid    (dmem_valid),
        .dmem_ren      (dmem_ren),
        .dmem_wen      (dmem_wen),
        .dmem_size     (dmem_size),
        .dmem_addr     (dmem_addr),
        .dmem_wdata    (dmem_wdata),
        .dmem_rdata    (dmem_rdata),
        .dmem_ready    (dmem_ready),
        .m_axi_awid    (m_axi_dmem_awid),
        .m_axi_awaddr  (m_axi_dmem_awaddr),
        .m_axi_awlen   (m_axi_dmem_awlen),
        .m_axi_awsize  (m_axi_dmem_awsize),
        .m_axi_awburst (m_axi_dmem_awburst),
        .m_axi_awprot  (m_axi_dmem_awprot),
        .m_axi_awvalid (m_axi_dmem_awvalid),
        .m_axi_awready (m_axi_dmem_awready),
        .m_axi_wdata   (m_axi_dmem_wdata),
        .m_axi_wstrb   (m_axi_dmem_wstrb),
        .m_axi_wlast   (m_axi_dmem_wlast),
        .m_axi_wvalid  (m_axi_dmem_wvalid),
        .m_axi_wready  (m_axi_dmem_wready),
        .m_axi_bid     (m_axi_dmem_bid),
        .m_axi_bresp   (m_axi_dmem_bresp),
        .m_axi_bvalid  (m_axi_dmem_bvalid),
        .m_axi_bready  (m_axi_dmem_bready),
        .m_axi_arid    (m_axi_dmem_arid),
        .m_axi_araddr  (m_axi_dmem_araddr),
        .m_axi_arlen   (m_axi_dmem_arlen),
        .m_axi_arsize  (m_axi_dmem_arsize),
        .m_axi_arburst (m_axi_dmem_arburst),
        .m_axi_arprot  (m_axi_dmem_arprot),
        .m_axi_arvalid (m_axi_dmem_arvalid),
        .m_axi_arready (m_axi_dmem_arready),
        .m_axi_rid     (m_axi_dmem_rid),
        .m_axi_rdata   (m_axi_dmem_rdata),
        .m_axi_rresp   (m_axi_dmem_rresp),
        .m_axi_rlast   (m_axi_dmem_rlast),
        .m_axi_rvalid  (m_axi_dmem_rvalid),
        .m_axi_rready  (m_axi_dmem_rready)
    );

endmodule
