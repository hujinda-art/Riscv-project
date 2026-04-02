`timescale 1ns / 1ps
`include "IF.v"
`include "IF_ID_reg.v"
`include "ID.v"
`include "ID_EX_reg.v"
`include "EX.v"
`include "../module/register.v"

module core_top (
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

    wire [31:0] if_pc_w;
    wire [31:0] if_pc_plus4_w;
    wire [31:0] if_instr;
    wire        if_instr_valid;

    wire        jump_if;
    wire [31:0] pc_jump_if;
    wire [31:0] instr_to_id;

    localparam [31:0] NOP = 32'h00000013;

    wire [6:0]  id_fun7;
    wire [4:0]  id_rs2, id_rs1, id_rd;
    wire [2:0]  id_fuc3;
    wire [6:0]  id_opcode;
    wire [31:0] id_imm;
    wire        id_use_rs1, id_use_rs2, id_is_branch, id_is_jump;
    wire        id_is_jalr, id_is_load, id_is_store, id_reg_we;

    wire        ex_reg_write_en;
    wire        ex_use_rs1, ex_use_rs2, ex_is_branch;
    wire        ex_is_jalr, ex_is_load, ex_is_store;

    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    wire        ex_branch_taken;
    wire [31:0] ex_pc_branch;
    wire        ex_jalr;
    wire [31:0] ex_pc_jalr;
    wire        ex_mem_ren;
    wire        ex_mem_wen;

    reg_file_bram u_regfile (
        .clk(clk),
        .we(1'b0),
        .waddr(5'b0),
        .wdata(32'b0),
        .raddr1(rs1_out),
        .rdata1(rf_rdata1),
        .raddr2(rs2_out),
        .rdata2(rf_rdata2)
    );

    IF_stage u_if (
        .clk(clk),
        .rst_n(rst_n),
        .stall_pc(stall),
        .flush(flush),
        .exception(exception),
        .pc_exception(pc_exception),
        .interrupt(interrupt),
        .pc_interrupt(pc_interrupt),
        .jalr(ex_jalr),
        .pc_jalr(ex_pc_jalr),
        .jump(jump_if),
        .pc_jump(pc_jump_if),
        .branch(ex_branch_taken),
        .pc_branch(ex_pc_branch),
        .if_pc(if_pc_w),
        .if_pc_plus4(if_pc_plus4_w),
        .instr_out(if_instr),
        .instr_valid_out(if_instr_valid)
    );

    IF_ID_reg u_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .jump_ex(1'b0),
        .pc_jump_ex(32'b0),
        .if_pc(if_pc_w),
        .if_pc_plus4(if_pc_plus4_w),
        .instr_in(if_instr),
        .instr_valid_in(if_instr_valid),
        .id_pc(id_pc),
        .id_pc_plus4(id_pc_plus4),
        .instr_out(instr_out),
        .instr_valid_out(instr_valid_out),
        .jump_out(jump_if),
        .pc_jump_out(pc_jump_if),
        .instr_to_id(instr_to_id)
    );

    ID_stage u_id (
        .instr_in(instr_to_id),
        .fun7(id_fun7),
        .rs2(id_rs2),
        .rs1(id_rs1),
        .fuc3(id_fuc3),
        .opcode(id_opcode),
        .rd(id_rd),
        .imm_out(id_imm),
        .use_rs1(id_use_rs1),
        .use_rs2(id_use_rs2),
        .is_branch(id_is_branch),
        .is_jump(id_is_jump),
        .is_jalr(id_is_jalr),
        .is_load(id_is_load),
        .is_store(id_is_store),
        .reg_write_en(id_reg_we)
    );

    ID_EX_reg u_id_ex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .id_pc_in(id_pc),
        .id_pc_plus4_in(id_pc_plus4),
        // 在进入 EX 前把 JAL 清成气泡：PC 已在 IF/ID 阶段提前重定向，
        // 因而不再让 JAL 指令进入 ID/EX->EX 的执行/访存通路。
        .instr_in(id_is_jump ? NOP : instr_to_id),
        .instr_valid_in(id_is_jump ? 1'b0 : instr_valid_out),
        .fun7_in(id_fun7),
        .rs1_in(id_rs1),
        .rs2_in(id_rs2),
        .fuc3_in(id_fuc3),
        .opcode_in(id_opcode),
        .rd_in(id_rd),
        .imm_in(id_imm),
        .reg_write_en_in(id_reg_we),
        .use_rs1_in(id_use_rs1),
        .use_rs2_in(id_use_rs2),
        .is_branch_in(id_is_branch),
        .is_jalr_in(id_is_jalr),
        .is_load_in(id_is_load),
        .is_store_in(id_is_store),
        .ex_pc(ex_pc_out),
        .ex_pc_plus4(ex_pc_plus4_out),
        .ex_instr(ex_instr_out),
        .ex_instr_valid(ex_instr_valid_out),
        .ex_fun7(fun7_out),
        .ex_rs1(rs1_out),
        .ex_rs2(rs2_out),
        .ex_fuc3(fuc3_out),
        .ex_opcode(opcode_out),
        .ex_rd(rd_out),
        .ex_imm(ex_imm_out),
        .ex_reg_write_en(ex_reg_write_en),
        .ex_use_rs1(ex_use_rs1),
        .ex_use_rs2(ex_use_rs2),
        .ex_is_branch(ex_is_branch),
        .ex_is_jalr(ex_is_jalr),
        .ex_is_load(ex_is_load),
        .ex_is_store(ex_is_store)
    );

    EX_stage u_ex (
        .ex_instr_valid(ex_instr_valid_out),
        .ex_pc(ex_pc_out),
        .ex_pc_plus4(ex_pc_plus4_out),
        .ex_fun7(fun7_out),
        .ex_rs1(rs1_out),
        .ex_rs2(rs2_out),
        .ex_fuc3(fuc3_out),
        .ex_opcode(opcode_out),
        .ex_imm(ex_imm_out),
        .ex_is_branch(ex_is_branch),
        .ex_is_jalr(ex_is_jalr),
        .ex_is_load(ex_is_load),
        .ex_is_store(ex_is_store),
        .rs1_data(rf_rdata1),
        .rs2_data(rf_rdata2),
        .ex_result(ex_result_out),
        .mem_addr(ex_mem_addr_out),
        .mem_wdata(ex_mem_wdata_out),
        .mem_read_en(ex_mem_ren),
        .mem_write_en(ex_mem_wen),
        .branch_taken(ex_branch_taken),
        .pc_branch(ex_pc_branch),
        .jalr(ex_jalr),
        .pc_jalr(ex_pc_jalr)
    );

endmodule
