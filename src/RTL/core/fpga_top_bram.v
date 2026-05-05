`timescale 1ns / 1ps
//
// fpga_top_bram — BRAM 直连路径（无 Cache，无 AXI）
// CPU 直接连接片上 inst_mem + data_mem
//
// 上板前请将以下源文件加入 Vivado 工程：
//   src/RTL/core/soc_top_bram.v
//   src/RTL/core/core_top.v 及所有子模块
//   src/RTL/memory/inst_mem.v, inst_mem_program.vh
//   src/RTL/memory/data_mem.v
//

`include "soc_top_bram.v"

module fpga_top_bram (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led
);

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

    (* dont_touch = "yes" *)
    soc_top_bram u_soc_top (
        .clk               (clk),
        .rst_n             (rst_n),
        .stall             (1'b0),
        .flush             (1'b0),
        .exception         (1'b0),
        .pc_exception      (32'b0),
        .interrupt         (1'b0),
        .pc_interrupt      (32'b0),
        .id_pc             (id_pc_w),
        .id_pc_plus4       (id_pc_plus4_w),
        .instr_out         (instr_out_w),
        .instr_valid_out   (instr_valid_out_w),
        .fun7_out          (fun7_out_w),
        .rs2_out           (rs2_out_w),
        .rs1_out           (rs1_out_w),
        .fuc3_out          (fuc3_out_w),
        .opcode_out        (opcode_out_w),
        .rd_out            (rd_out_w),
        .ex_pc_out         (ex_pc_out_w),
        .ex_pc_plus4_out   (ex_pc_plus4_out_w),
        .ex_instr_out      (ex_instr_out_w),
        .ex_instr_valid_out(ex_instr_valid_out_w),
        .ex_imm_out        (ex_imm_out_w),
        .ex_result_out     (ex_result_out_w),
        .ex_mem_addr_out   (ex_mem_addr_out_w),
        .ex_mem_wdata_out  (ex_mem_wdata_out_w)
    );

    assign led = ex_result_out_w[7:0];

endmodule
