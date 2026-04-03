`timescale 1ns / 1ps
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
    wire        imem_rvalid;

    // ---- 数据总线 ----
    wire        dmem_wen;
    wire        dmem_ren;
    wire [1:0]  dmem_size;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        dmem_rvalid;

    // ---- 理想存储器桥接 ----
    // inst_mem 为组合读，同拍返回，rvalid 恒为 1
    assign imem_rvalid = 1'b1;
    // data_mem 为同步读，1 拍延迟已由 MEM/WB 级间寄存器对齐吸收，
    // 理想桥接下 rvalid 恒为 1（Phase 3 慢速桥接时此处改为带延迟的状态机）
    assign dmem_rvalid = 1'b1;

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
        .imem_rvalid      (imem_rvalid),
        // 数据总线
        .dmem_wen         (dmem_wen),
        .dmem_ren         (dmem_ren),
        .dmem_size        (dmem_size),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_rdata       (dmem_rdata),
        .dmem_rvalid      (dmem_rvalid)
    );

    // 指令存储器（组合读，取指无额外延迟）
    inst_mem u_inst_mem (
        .pc_addr (imem_addr),
        .inst    (imem_rdata)
    );

    // 数据存储器（同步读，1 拍延迟由 MEM/WB 级间寄存器对齐）
    data_mem u_data_mem (
        .clk      (clk),
        .write_en (dmem_wen),
        .size     (dmem_size),
        .address  (dmem_addr),
        .data_in  (dmem_wdata),
        .data_out (dmem_rdata)
    );

endmodule
