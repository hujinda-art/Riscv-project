`timescale 1ns / 1ps
`include "../include/soc_config.vh"
`include "../include/soc_addr_map.vh"
//
// SoC 顶层集成壳：CPU 核 + 指令存储器 + 数据存储器。
// 此文件为 SoC 边界，后续可将存储器替换为 AXI Master 适配器。
//
`include "core_top.v"
`include "../memory/inst_mem.v"
`include "../memory/data_mem.v"

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
    output wire [31:0] ex_mem_wdata_out
);

    // ---- 指令总线 ----
    wire [31:0] imem_addr;
    wire        imem_req;
    wire [31:0] imem_rdata;
    wire        imem_ready;

    // ---- 数据总线 ----
    wire        dmem_wen;
    wire        dmem_ren;
    wire        dmem_valid;
    wire [1:0]  dmem_size;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;

    // ---- 理想存储器桥接 ----
    // imem/dmem 都走 req/ready 握手，ready 由各自存储器模块输出。

    core_top u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall),
        .flush            (flush),
        .exception        (exception),
        .pc_exception     (pc_exception),
        .interrupt        (interrupt),
        .pc_interrupt     (pc_interrupt),
        .id_pc            (id_pc),
        .id_pc_plus4      (id_pc_plus4),
        .instr_out        (instr_out),
        .instr_valid_out  (instr_valid_out),
        .fun7_out         (fun7_out),
        .rs2_out          (rs2_out),
        .rs1_out          (rs1_out),
        .fuc3_out         (fuc3_out),
        .opcode_out       (opcode_out),
        .rd_out           (rd_out),
        .ex_pc_out        (ex_pc_out),
        .ex_pc_plus4_out  (ex_pc_plus4_out),
        .ex_instr_out     (ex_instr_out),
        .ex_instr_valid_out(ex_instr_valid_out),
        .ex_imm_out       (ex_imm_out),
        .ex_result_out    (ex_result_out),
        .ex_mem_addr_out  (ex_mem_addr_out),
        .ex_mem_wdata_out (ex_mem_wdata_out),
        // 指令总线
        .imem_addr        (imem_addr),
        .imem_req         (imem_req),
        .imem_rdata       (imem_rdata),
        .imem_ready       (imem_ready),
        // 数据总线
        .dmem_wen         (dmem_wen),
        .dmem_ren         (dmem_ren),
        .dmem_valid       (dmem_valid),
        .dmem_size        (dmem_size),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_rdata       (dmem_rdata),
        .dmem_ready       (dmem_ready)
    );

    // 指令存储器：程序已内联在 inst_mem_program.vh（由 inst_mem.v `include），
    // 综合/上板不依赖 .hex 文件，也无需把 .hex 加入 Vivado 工程。
    inst_mem u_inst_mem (
        .clk     (clk),
        .req     (imem_req),
        .pc_addr (imem_addr),
        .inst    (imem_rdata),
        .ready   (imem_ready)
    );

    // 数据存储器（同步读，1 拍延迟由 MEM/WB 级间寄存器对齐）
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
