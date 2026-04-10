`timescale 1ns / 1ps
//
// ID/EX 级间寄存器：锁存译码结果与 PC 上下文，供执行级使用。
// stall：保持（与 IF/IF_ID 冒险停顿时一并使用）；flush：注入气泡（NOP + valid=0）。
//
module ID_EX_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] id_pc_in,
    input  wire [31:0] id_pc_plus4_in,
    input  wire [31:0] instr_in,
    input  wire        instr_valid_in,
    input  wire [6:0]  fun7_in,
    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [2:0]  fuc3_in,
    input  wire [6:0]  opcode_in,
    input  wire [4:0]  rd_in,
    input  wire [31:0] imm_in,
    input  wire        reg_write_en_in,
    input  wire        use_rs1_in,//冗余信号，后续不扩展时可以删除
    input  wire        use_rs2_in,
    input  wire        is_branch_in,
    input  wire        is_jalr_in,
    input  wire        is_load_in,
    input  wire        is_store_in,
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_pc_plus4,
    output reg  [31:0] ex_instr,
    output reg         ex_instr_valid,
    output reg  [6:0]  ex_fun7,
    output reg  [4:0]  ex_rs1,
    output reg  [4:0]  ex_rs2,
    output reg  [2:0]  ex_fuc3,
    output reg  [6:0]  ex_opcode,
    output reg  [4:0]  ex_rd,
    output reg  [31:0] ex_imm,
    output reg         ex_reg_write_en,
    output reg         ex_use_rs1,
    output reg         ex_use_rs2,
    output reg         ex_is_branch,    
    output reg         ex_is_jalr,
    output reg         ex_is_load,
    output reg         ex_is_store
);

    localparam NOP = 32'h00000013;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc            <= 32'b0;
            ex_pc_plus4      <= 32'h4;
            ex_instr         <= NOP;
            ex_instr_valid   <= 1'b0;
            ex_fun7          <= 7'b0;
            ex_rs1           <= 5'b0;
            ex_rs2           <= 5'b0;
            ex_fuc3          <= 3'b0;
            ex_opcode        <= 7'b0;
            ex_rd            <= 5'b0;
            ex_imm           <= 32'b0;
            ex_reg_write_en  <= 1'b0;
            ex_use_rs1       <= 1'b0;
            ex_use_rs2       <= 1'b0;
            ex_is_branch     <= 1'b0;
            ex_is_jalr       <= 1'b0;
            ex_is_load       <= 1'b0;
            ex_is_store      <= 1'b0;
        end else if (flush) begin
            ex_pc            <= 32'b0;
            ex_pc_plus4      <= 32'b0;
            ex_instr         <= NOP;
            ex_instr_valid   <= 1'b0;
            ex_fun7          <= 7'b0;
            ex_rs1           <= 5'b0;
            ex_rs2           <= 5'b0;
            ex_fuc3          <= 3'b0;
            ex_opcode        <= 7'b0;
            ex_rd            <= 5'b0;
            ex_imm           <= 32'b0;
            ex_reg_write_en  <= 1'b0;
            ex_use_rs1       <= 1'b0;
            ex_use_rs2       <= 1'b0;
            ex_is_branch     <= 1'b0;
            ex_is_jalr       <= 1'b0;
            ex_is_load       <= 1'b0;
            ex_is_store      <= 1'b0;
        end else if (stall) begin
            ex_pc            <= ex_pc;
            ex_pc_plus4      <= ex_pc_plus4;
            ex_instr         <= ex_instr;
            ex_instr_valid   <= ex_instr_valid;
            ex_fun7          <= ex_fun7;
            ex_rs1           <= ex_rs1;
            ex_rs2           <= ex_rs2;
            ex_fuc3          <= ex_fuc3;
            ex_opcode        <= ex_opcode;
            ex_rd            <= ex_rd;
            ex_imm           <= ex_imm;
            ex_reg_write_en  <= ex_reg_write_en;
            ex_use_rs1       <= ex_use_rs1;
            ex_use_rs2       <= ex_use_rs2;
            ex_is_branch     <= ex_is_branch;
            ex_is_jalr       <= ex_is_jalr;
            ex_is_load       <= ex_is_load;
            ex_is_store      <= ex_is_store;
        end else begin
            ex_pc            <= id_pc_in;
            ex_pc_plus4      <= id_pc_plus4_in;
            ex_instr         <= instr_in;
            ex_instr_valid   <= instr_valid_in;
            ex_fun7          <= fun7_in;
            ex_rs1           <= rs1_in;
            ex_rs2           <= rs2_in;
            ex_fuc3          <= fuc3_in;
            ex_opcode        <= opcode_in;
            ex_rd            <= rd_in;
            ex_imm           <= imm_in;
            ex_reg_write_en  <= reg_write_en_in;
            ex_use_rs1       <= use_rs1_in;
            ex_use_rs2       <= use_rs2_in;
            ex_is_branch     <= is_branch_in;
            ex_is_jalr       <= is_jalr_in;
            ex_is_load       <= is_load_in;
            ex_is_store      <= is_store_in;
        end
    end

endmodule
