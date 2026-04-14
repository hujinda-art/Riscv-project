`timescale 1ns / 1ps
//
// ID 阶段
//
module ID_stage(
    input  wire [31:0] instr_in,
    output wire [6:0]  fun7,
    output wire [4:0]  rs2,
    output wire [4:0]  rs1,
    output wire [2:0]  fuc3,
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [31:0] imm_out,
    output wire        use_rs1,
    output wire        use_rs2,
    output wire        is_branch,
    output wire        is_jump,
    output wire        is_jalr,
    output wire        is_load,
    output wire        is_store,
    output wire        reg_write_en
);

    assign fun7   = instr_in[31:25];
    assign rs2    = instr_in[24:20];
    assign rs1    = instr_in[19:15];
    assign fuc3   = instr_in[14:12];
    assign opcode = instr_in[6:0];
    assign rd     = instr_in[11:7];

    // 判断指令类型
    wire is_r   = (opcode == 7'b0110011);
    wire is_i   = (opcode == 7'b0010011);
    wire is_lui = (opcode == 7'b0110111);
    wire is_aui = (opcode == 7'b0010111);

    assign is_load   = (opcode == 7'b0000011);
    assign is_store  = (opcode == 7'b0100011);
    assign is_branch = (opcode == 7'b1100011);
    assign is_jalr   = (opcode == 7'b1100111);
    assign is_jump   = (opcode == 7'b1101111);

    assign use_rs1 = is_r | is_i | is_load | is_store | is_branch | is_jalr;
    assign use_rs2 = is_r | is_store | is_branch;

    assign reg_write_en = is_r | is_i | is_load | is_jalr | is_jump | is_lui | is_aui;

    // 立即数生成
    reg [31:0] imm_reg;
    always @(*) begin
        case (opcode)
            7'b0100011: // S-type
                imm_reg = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
            7'b1100011: // B-type
                imm_reg = {{19{instr_in[31]}}, instr_in[31], instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
            7'b1101111: // J-type (JAL)
                imm_reg = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};
            7'b0110111, // U-type (LUI)
            7'b0010111: // U-type (AUIPC)
                imm_reg = {instr_in[31:12], 12'b0};
            default: // I-type and all others
                imm_reg = {{20{instr_in[31]}}, instr_in[31:20]};
        endcase
    end
    assign imm_out = imm_reg;

endmodule
