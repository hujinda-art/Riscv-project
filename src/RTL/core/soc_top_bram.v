`timescale 1ns / 1ps
`include "../include/soc_config.vh"
`include "../include/soc_addr_map.vh"
//
// SoC 顶层（片内 BRAM 版）：CPU + L1 I$ + inst_mem + data_mem。
// 用于 RTL 仿真、fpga_top 等不经过 AXI BD 的场景。
// 若使用 Vivado BD + AXI SmartConnect，请使用 soc_top.v（AXI 主口版）。
//
`include "core_top.v"
`include "../memory/inst_mem.v"
`include "../memory/data_mem.v"

module soc_top_bram (
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

    wire [31:0] imem_addr;
    wire        imem_req;
    wire [31:0] imem_rdata;
    wire        imem_ready;

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

    inst_mem u_inst_mem (
        .clk     (clk),
        .req     (imem_req),
        .pc_addr (imem_addr),
        .inst    (imem_rdata),
        .ready   (imem_ready)
    );

    data_mem u_data_mem (
        .clk      (clk),
        .valid    (dmem_valid),
        .read_en  (dmem_ren),
        .write_en (dmem_wen),
        .size     (dmem_size),
        .address  (dmem_addr),
        .data_in  (dmem_wdata),
        .data_out (dmem_rdata),
        .ready    (dmem_ready)
    );

endmodule
