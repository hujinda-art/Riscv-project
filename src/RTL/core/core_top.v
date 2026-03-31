`timescale 1ns / 1ps
`include "IF.v"
`include "IF_ID_reg.v"
`include "ID.v"

module core_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        stall,
    input  wire        flush,
    input  wire        exception,
    input  wire [31:0] pc_exception,
    input  wire        interrupt,
    input  wire [31:0] pc_interrupt,
    input  wire        jalr,
    input  wire [31:0] pc_jalr,
    input  wire        jump,
    input  wire [31:0] pc_jump,
    input  wire        branch,
    input  wire [31:0] pc_branch,

    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    output wire [31:0] pc_current_out,
    output wire [31:0] pc_plus_4_out,
    output wire [31:0] instr_out,
    output wire        instr_valid_out,

    output wire [6:0]  fun7_out,
    output wire [4:0]  rs2_out,
    output wire [4:0]  rs1_out,
    output wire [2:0]  fuc3_out,
    output wire [6:0]  opcode_out,
    output wire [4:0]  rd_out
);

    wire [31:0] if_pc_current;
    wire [31:0] if_pc_plus_4;
    wire [31:0] if_instr;
    wire        if_instr_valid;

    IF_stage u_if (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .exception(exception),
        .pc_exception(pc_exception),
        .interrupt(interrupt),
        .pc_interrupt(pc_interrupt),
        .jalr(jalr),
        .pc_jalr(pc_jalr),
        .jump(jump),
        .pc_jump(pc_jump),
        .branch(branch),
        .pc_branch(pc_branch),
        .imem_addr(imem_addr),
        .imem_data(imem_data),
        .pc_current_out(if_pc_current),
        .pc_plus_4_out(if_pc_plus_4),
        .instr_out(if_instr),
        .instr_valid_out(if_instr_valid)
    );

    IF_ID_reg u_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .pc_current_in(if_pc_current),
        .pc_plus_4_in(if_pc_plus_4),
        .instr_in(if_instr),
        .instr_valid_in(if_instr_valid),
        .pc_current_out(pc_current_out),
        .pc_plus_4_out(pc_plus_4_out),
        .instr_out(instr_out),
        .instr_valid_out(instr_valid_out)
    );

    ID_stage u_id (
        .instr_in(instr_out),
        .fun7(fun7_out),
        .rs2(rs2_out),
        .rs1(rs1_out),
        .fuc3(fuc3_out),
        .opcode(opcode_out),
        .rd(rd_out)
    );

endmodule
