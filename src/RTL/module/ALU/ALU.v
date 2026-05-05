`timescale 1ns / 1ps
`include "cla_adder_32bit.v"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/13 18:55:32
// Design Name: 
// Module Name: ALU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//posible development:power optimization,configurable bit width, multiple and discorder
module ALU(
    input  [31:0] a,b,
    input  [4:0]  op,
    
    output reg [31:0] result,
    output reg            cout,
    output reg         condition
    );
    
    reg [31:0] logic_result, shift_result, compare_result;
    
    wire [31:0] arith_result_1;
    wire arith_cin;
    wire [31:0] arith_b;
    wire cout_ALU;
    // ============================================================
    // M extension (RV32M) — 暂时 stub 为 0，待多周期除法器完善后启用
    // ============================================================
    // MUL：有符号相乘，取低 32 位
    wire [31:0] mul_result    = 32'b0;
    // MULH：有符号×有符号，取高 32 位
    wire [31:0] mulh_result   = 32'b0;
    // MULHU：无符号×无符号，取高 32 位
    wire [31:0] mulhu_result  = 32'b0;
    // MULHSU：有符号×无符号，取高 32 位
    wire [31:0] mulhsu_result = 32'b0;
    // DIV/DIVU/REM/REMU
    wire [31:0] div_result    = 32'b0;
    wire [31:0] divu_result   = 32'b0;
    wire [31:0] rem_result    = 32'b0;
    wire [31:0] remu_result   = 32'b0;
    
    assign arith_b = (op == 5'b00000) ? b : ~b;
    assign arith_cin = (op == 5'b00000) ? 1'b0 : 1'b1;
    adder_32bit u_ALU_adder(
        .a(a),
        .b(arith_b),
        .c_in(arith_cin),
        .result(arith_result_1),
        .c_out(cout_ALU)   
     );
    
    always @(*) begin
        case(op)
            5'b00000: cout = cout_ALU;
            5'b00001: cout = ~cout_ALU;
            5'b00010: cout = 1'b0;
            default: cout = 1'b0;
        endcase
    end
    
    always @(*) begin
        case (op)
            5'b00100: logic_result = a & b;
            5'b00101: logic_result = a | b;
            5'b00110: logic_result = a ^ b;
            default: logic_result = 32'b0;
        endcase
    end
    
    
    wire [31:0] shift_mask; 
    assign shift_mask = {32{a[31]}} << (32 - b[4:0]);
    always @(*) begin
        case (op)
            5'b01000: shift_result = a << b[4:0];
            5'b01001: shift_result = a >> b[4:0];
            5'b01010: shift_result = (a >> b[4:0]) | shift_mask;
            default: shift_result = 32'b0;
        endcase    
    end
    
   always @(*) begin
        case(op)
            5'b10000: condition = (a == b) ? 1'b1 : 1'b0;
            5'b10001: condition = (a != b) ? 1'b1 : 1'b0;
            5'b10010: condition = (a < b) ? 1'b1 : 1'b0;
            5'b10011: condition = (a >= b) ? 1'b1 : 1'b0;
            5'b10110: condition = ($signed(a) < $signed(b)) ? 1'b1: 1'b0;
            5'b10111: condition = ($signed(a) >= $signed(b)) ? 1'b1 : 1'b0;
            default:  condition = 1'b0;
        endcase
    end
    always @(*) begin
        case(op)
           5'b01100: compare_result = $signed(a) < $signed(b) ? 32'd1 : 32'd0;
           5'b01101: compare_result = a < b ? 32'd1 : 32'd0;
           default: compare_result = 32'b0;
        endcase
    end
    
    always @(*) begin
        case (op)
            // Arithmetic
            5'b00000: result = arith_result_1;    // add
            5'b00001: result = arith_result_1;    // sub
            // Multiply
            5'b00010: result = mul_result;        // MUL
            5'b00011: result = mulh_result;       // MULH
            // Logic
            5'b00100: result = logic_result;      // and
            5'b00101: result = logic_result;      // or
            5'b00110: result = logic_result;      // xor
            5'b00111: result = mulhsu_result;     // MULHSU
            // Shift
            5'b01000: result = shift_result;      // sll
            5'b01001: result = shift_result;      // srl
            5'b01010: result = shift_result;      // sra
            5'b01011: result = mulhu_result;      // MULHU
            // Compare
            5'b01100: result = compare_result;    // slt
            5'b01101: result = compare_result;    // sltu
            5'b01110: result = div_result;        // DIV
            5'b01111: result = divu_result;       // DIVU
            // Branch conditions (result unused, but set for DIV/REM reuse)
            5'b10000: result = 32'b0;             // beq
            5'b10001: result = rem_result;        // REM (reuses BNE slot)
            5'b10010: result = 32'b0;             // bltu
            5'b10011: result = 32'b0;             // bgeu
            5'b10100: result = remu_result;       // REMU
            5'b10110: result = 32'b0;             // blt
            5'b10111: result = 32'b0;             // bge
            default:  result = 32'b0;
        endcase
    end         
endmodule
