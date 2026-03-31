`timescale 1ns / 1ps
module ID_stage(
    input  wire [31:0] instr_in,
    output wire [6:0]  fun7,
    output wire [4:0]  rs2,
    output wire [4:0]  rs1,
    output wire [2:0]  fuc3,
    output wire [6:0]  opcode,
    output wire [4:0]  rd
);

    // RISC-V 指令字段按高位到低位解析：
    // [31:25] fun7, [24:20] rs2, [19:15] rs1, [14:12] fuc3, [6:0] opcode
    assign fun7   = instr_in[31:25];
    assign rs2    = instr_in[24:20];
    assign rs1    = instr_in[19:15];
    assign fuc3   = instr_in[14:12];
    assign opcode = instr_in[6:0];
    assign rd     = instr_in[11:7];

endmodule