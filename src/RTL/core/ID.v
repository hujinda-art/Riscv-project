`timescale 1ns / 1ps
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

    // RISC-V 指令字段按高位到低位解析：
    // [31:25] fun7, [24:20] rs2, [19:15] rs1, [14:12] fuc3, [6:0] opcode
    assign fun7   = instr_in[31:25];
    assign rs2    = instr_in[24:20];
    assign rs1    = instr_in[19:15];
    assign fuc3   = instr_in[14:12];
    assign opcode = instr_in[6:0];
    assign rd     = instr_in[11:7];

  
    localparam [6:0] OPCODE_R_TYPE = 7'b0110011;
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;
    localparam [6:0] OPCODE_JAL    = 7'b1101111;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111;

    wire [31:0] imm_i;
    wire [31:0] imm_s;
    wire [31:0] imm_b;
    wire [31:0] imm_u;
    wire [31:0] imm_j;

    assign imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
    assign imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
    assign imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
    assign imm_u = {instr_in[31:12], 12'b0};
    assign imm_j = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};

    assign is_branch = (opcode == OPCODE_BRANCH);
    assign is_jump   = (opcode == OPCODE_JAL);
    assign is_jalr   = (opcode == OPCODE_JALR);
    assign is_load   = (opcode == OPCODE_LOAD);
    assign is_store  = (opcode == OPCODE_STORE);

    assign use_rs1 = (opcode == OPCODE_R_TYPE) ||
                     (opcode == OPCODE_I_TYPE) ||
                     (opcode == OPCODE_LOAD)   ||
                     (opcode == OPCODE_STORE)  ||
                     (opcode == OPCODE_BRANCH) ||
                     (opcode == OPCODE_JALR);

    assign use_rs2 = (opcode == OPCODE_R_TYPE) ||
                     (opcode == OPCODE_STORE)  ||
                     (opcode == OPCODE_BRANCH);

    // x(rd) 写使能：store/branch 不写回，其他常见类型写回
    assign reg_write_en = (opcode == OPCODE_R_TYPE) ||
                          (opcode == OPCODE_I_TYPE) ||
                          (opcode == OPCODE_LOAD)   ||
                          (opcode == OPCODE_JALR)   ||
                          (opcode == OPCODE_JAL)    ||
                          (opcode == OPCODE_LUI)    ||
                          (opcode == OPCODE_AUIPC);

    // 统一立即数输出，供 EX 阶段选择使用
    assign imm_out = (opcode == OPCODE_STORE)  ? imm_s :
                     (opcode == OPCODE_BRANCH) ? imm_b :
                     (opcode == OPCODE_JAL)    ? imm_j :
                     (opcode == OPCODE_LUI ||
                      opcode == OPCODE_AUIPC)  ? imm_u :
                                                  imm_i;

endmodule