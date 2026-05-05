`timescale 1ns / 1ps
`include "../include/soc_config.vh"
`include "../include/soc_addr_map.vh"
//
// SoC 顶层（片内 BRAM + L1 D$）：CPU + inst_mem + L1_Cache_DATA + data_mem。
// 用于验证 data cache 集成后的系统级行为。
//
`include "core_top.v"
`include "../memory/inst_mem.v"
`include "../module/Cache/L1_Cache_DATA.v"
`include "../memory/data_mem.v"

module soc_top_bram_dcache (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        stall,
    input  wire        flush,
    input  wire        exception,
    input  wire [31:0] pc_exception,
    input  wire        interrupt,
    input  wire [31:0] pc_interrupt,

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
    output wire [31:0] ex_mem_wdata_out
);

    // ---- CPU 侧指令总线（直连 inst_mem）----
    wire [31:0] imem_addr;
    wire        imem_req;
    wire [31:0] imem_rdata;
    wire        imem_ready;

    // ---- CPU 侧数据总线 ----
    wire        cpu_dmem_wen;
    wire        cpu_dmem_ren;
    wire        cpu_dmem_valid;
    wire [1:0]  cpu_dmem_size;
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [31:0] cpu_dmem_rdata;
    wire        cpu_dmem_ready;

    // ---- D$ 与 data_mem 之间 ----
    wire        dc_mem_valid;
    wire        dc_mem_read_en;
    wire        dc_mem_write_en;
    wire [1:0]  dc_mem_size;
    wire [31:0] dc_mem_addr;
    wire [31:0] dc_mem_wdata;
    wire [31:0] dc_mem_rdata;
    wire        dc_mem_ready;

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
        .dmem_wen          (cpu_dmem_wen),
        .dmem_ren          (cpu_dmem_ren),
        .dmem_valid        (cpu_dmem_valid),
        .dmem_size         (cpu_dmem_size),
        .dmem_addr         (cpu_dmem_addr),
        .dmem_wdata        (cpu_dmem_wdata),
        .dmem_rdata        (cpu_dmem_rdata),
        .dmem_ready        (cpu_dmem_ready)
    );

    inst_mem u_inst_mem (
        .clk     (clk),
        .req     (imem_req),
        .pc_addr (imem_addr),
        .inst    (imem_rdata),
        .ready   (imem_ready)
    );

    L1_Cache_DATA u_dcache (
        .clk          (clk),
        .rst_n        (rst_n),
        .dmem_valid   (cpu_dmem_valid),
        .dmem_ren     (cpu_dmem_ren),
        .dmem_wen     (cpu_dmem_wen),
        .dmem_size    (cpu_dmem_size),
        .dmem_addr    (cpu_dmem_addr),
        .dmem_wdata   (cpu_dmem_wdata),
        .dmem_rdata   (cpu_dmem_rdata),
        .dmem_ready   (cpu_dmem_ready),
        .mem_valid    (dc_mem_valid),
        .mem_read_en  (dc_mem_read_en),
        .mem_write_en (dc_mem_write_en),
        .mem_size     (dc_mem_size),
        .mem_addr     (dc_mem_addr),
        .mem_wdata    (dc_mem_wdata),
        .mem_rdata    (dc_mem_rdata),
        .mem_ready    (dc_mem_ready)
    );

    data_mem u_data_mem (
        .clk      (clk),
        .valid    (dc_mem_valid),
        .read_en  (dc_mem_read_en),
        .write_en (dc_mem_write_en),
        .size     (dc_mem_size),
        .address  (dc_mem_addr),
        .data_in  (dc_mem_wdata),
        .data_out (dc_mem_rdata),
        .ready    (dc_mem_ready)
    );

endmodule
