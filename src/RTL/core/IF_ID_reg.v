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
    input  wire        jump_ex,
    input  wire [31:0] pc_jump_ex,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_plus4,
    input  wire [31:0] instr_in,
    input  wire        instr_valid_in,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] instr_out,
    output reg         instr_valid_out,
    output wire        jump_out,
    output wire [31:0] pc_jump_out,
    output wire [31:0] instr_to_id
);

    localparam NOP = 32'h00000013;
    localparam [6:0] OPCODE_JAL = 7'b1101111;

    wire [31:0] imm_j = {{11{instr_out[31]}}, instr_out[31], instr_out[19:12],
                          instr_out[20], instr_out[30:21], 1'b0};
    wire        id_jal_taken  = (instr_out[6:0] == OPCODE_JAL);
    wire [31:0] id_jal_target = id_pc + imm_j;
    wire        jal_active    = id_jal_taken & instr_valid_out;

    reg         s_jal_seen;
    wire        stall_if_id = stall | (jal_active & ~s_jal_seen);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s_jal_seen <= 1'b0;
        else if (flush)
            s_jal_seen <= 1'b0;
        else
            s_jal_seen <= jal_active;
    end

    assign jump_out    = jump_ex | jal_active;
    assign pc_jump_out = jump_ex ? pc_jump_ex : id_jal_target;

    reg        id_ex_valid;
    reg [31:0] id_ex_instr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_valid <= 1'b0;
            id_ex_instr <= NOP;
        end else if (flush) begin
            id_ex_valid <= 1'b0;
            id_ex_instr <= NOP;
        end else if (id_ex_valid) begin
            id_ex_valid <= 1'b0;
        end else if (jal_active & ~s_jal_seen) begin
            id_ex_instr <= instr_out;
            id_ex_valid <= 1'b1;
        end
    end

    assign instr_to_id = id_ex_valid ? id_ex_instr : instr_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc           <= 32'h00000000;
            id_pc_plus4     <= 32'h00000004;
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (flush) begin
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (stall_if_id) begin
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
