`timescale 1ns / 1ps
//
// IF/ID 级间寄存器
//
module IF_ID_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_plus4,// if_pc / if_pc_plus4：来自 IF 的取指上下文，不直接驱动 PC。
    input  wire [31:0] instr_in,
    input  wire        instr_valid_in,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] instr_out,// id_pc / id_pc_plus4、instr_out：锁存后与指令对齐。
    output reg         instr_valid_out
    
);

    localparam NOP = 32'h00000013;

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc           <= 32'h00000000;
            id_pc_plus4     <= 32'h00000004;
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (flush) begin
            id_pc           <= 32'h00000000;
            id_pc_plus4     <= 32'h00000004;
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (stall) begin
            id_pc           <= id_pc;
            id_pc_plus4     <= id_pc_plus4;
            instr_out       <= instr_out;
            instr_valid_out <= instr_valid_out;
        end else begin
            id_pc           <= if_pc;
            id_pc_plus4     <= if_pc_plus4;
            instr_out       <= instr_in;
            instr_valid_out <= instr_valid_in;
        end
    end

endmodule
