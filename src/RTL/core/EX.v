`timescale 1ns / 1ps
//
// EX 阶段（组合）：ALU、分支/JALR 目标、访存地址与写数据。
// 无条件 JAL 已在 IF/ID 提前处理；此处仍处理 branch、JALR、load/store、算术与 LUI/AUIPC。
//
`include "../module/ALU/ALU.v"

module EX_stage (
    input  wire        ex_instr_valid,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc_plus4,
    input  wire [6:0]  ex_fun7,
    input  wire [4:0]  ex_rs1,
    input  wire [4:0]  ex_rs2,
    input  wire [2:0]  ex_fuc3,
    input  wire [6:0]  ex_opcode,
    input  wire [31:0] ex_imm,
    input  wire        ex_is_branch,
    input  wire        ex_is_jalr,
    input  wire        ex_is_load,
    input  wire        ex_is_store,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    output wire [31:0] ex_result,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire        mem_read_en,
    output wire        mem_write_en,
    output wire        branch_taken,
    output wire [31:0] pc_branch,
    output wire        jalr,
    output wire [31:0] pc_jalr
);

    localparam [6:0] OPCODE_R_TYPE = 7'b0110011;
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam [6:0] OPCODE_JALR   = 7'b1100111;
    localparam [6:0] OPCODE_LUI    = 7'b0110111;
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111;

    wire [31:0] alu_a;
    wire [31:0] alu_b;
    reg  [4:0]  alu_op;

    wire [31:0] alu_result;
    wire        alu_cond;
    wire        alu_cout;
    ALU u_alu (
        .a(alu_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result),
        .cout(alu_cout),
        .condition(alu_cond)
    );

    // 分支比较：fun3 -> ALU 条件类 op（与 ALU.v 中 encoding 一致）
    reg [4:0] branch_alu_op;
    always @(*) begin
        case (ex_fuc3)
            3'b000:  branch_alu_op = 5'b10000; // beq
            3'b001:  branch_alu_op = 5'b10001; // bne
            3'b100:  branch_alu_op = 5'b10110; // blt
            3'b101:  branch_alu_op = 5'b10111; // bge
            3'b110:  branch_alu_op = 5'b10010; // bltu
            3'b111:  branch_alu_op = 5'b10011; // bgeu
            default: branch_alu_op = 5'b00000;
        endcase
    end

    always @(*) begin
        if (ex_is_branch) begin
            alu_op = branch_alu_op;
        end else begin
            case (ex_opcode)
                OPCODE_R_TYPE: begin
                    case (ex_fuc3)
                        3'b000: begin
                            if (ex_fun7 == 7'b0100000)
                                alu_op = 5'b00001; // sub
                            else if (ex_fun7 == 7'b0000001)
                                alu_op = 5'b00010; // mul (RV32M)
                            else
                                alu_op = 5'b00000; // add
                        end
                        3'b010:  alu_op = 5'b01100; // slt
                        3'b011:  alu_op = 5'b01101; // sltu
                        3'b001:  alu_op = 5'b01000; // sll
                        3'b100:  alu_op = 5'b00110; // xor
                        3'b101:  alu_op = ex_fun7[5] ? 5'b01010 : 5'b01001; // sra / srl
                        3'b110:  alu_op = 5'b00101; // or
                        3'b111:  alu_op = 5'b00100; // and
                        default: alu_op = 5'b00000;
                    endcase
                end
                OPCODE_I_TYPE: begin
                    case (ex_fuc3)
                        3'b000:  alu_op = 5'b00000; // addi
                        3'b010:  alu_op = 5'b01100; // slti：结果用比较生成，ALU 仅占位
                        3'b011:  alu_op = 5'b01101; // sltiu
                        3'b100:  alu_op = 5'b00110; // xori
                        3'b110:  alu_op = 5'b00101; // ori
                        3'b111:  alu_op = 5'b00100; // andi
                        3'b001:  alu_op = 5'b01000; // slli
                        3'b101:  alu_op = ex_imm[10] ? 5'b01010 : 5'b01001; // srai / srli
                        default: alu_op = 5'b00000;
                    endcase
                end
                default: alu_op = 5'b00000;
            endcase
        end
    end

    assign alu_a = rs1_data;
    assign alu_b = (ex_opcode == OPCODE_R_TYPE || ex_is_branch) ? rs2_data : ex_imm;


    assign pc_branch    = ex_pc + ex_imm;
    assign pc_jalr      = (rs1_data + ex_imm) & ~32'd1;
    assign branch_taken = ex_instr_valid & ex_is_branch & alu_cond;
    assign jalr         = ex_instr_valid & ex_is_jalr;

    assign mem_addr     = rs1_data + ex_imm;
    assign mem_wdata    = rs2_data;
    assign mem_read_en  = ex_instr_valid & ex_is_load;
    assign mem_write_en = ex_instr_valid & ex_is_store;

    assign ex_result =
        !ex_instr_valid ? 32'b0 :
        (ex_opcode == OPCODE_LUI)                                       ? ex_imm :
        (ex_opcode == OPCODE_AUIPC)                                     ? (ex_pc + ex_imm) :
        (ex_opcode == OPCODE_JALR)                                      ? ex_pc_plus4 :
        (ex_opcode == OPCODE_LOAD || ex_opcode == OPCODE_STORE)         ? mem_addr :
        alu_result;

endmodule
