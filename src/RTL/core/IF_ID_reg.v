`timescale 1ns / 1ps
//
// IF/ID 级间寄存器（含提前 JAL 跳转与 ID 侧指令对齐）
// - if_pc / if_pc_plus4：来自 IF 的取指上下文，不直接驱动 PC。
// - id_pc / id_pc_plus4、instr_out：锁存后与指令对齐。
// - jump_out / pc_jump_out：送 IF→PC；合并本阶段 JAL 与后级 jump_ex（后级优先）。
// - stall：结构/数据冒险；JAL 首拍额外停顿 IF/ID 但不通过 stall 冻 PC（顶层 stall 只接 IF.stall_pc）。
//
module IF_ID_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_plus4,
    input  wire [31:0] instr_in,
    input  wire        instr_valid_in,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] instr_out,
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
