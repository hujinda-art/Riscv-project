`timescale 1ns / 1ps
`include"cla_adder_32bit.v"
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
    output reg         condition
    );
    
    reg [31:0] logic_result, shift_result, compare_result;
    
    wire [31:0] arith_result;
    wire arith_cin;
    wire [31:0] arith_b;
    assign arith_b = (op == 5'b00000) ? b : ~b;
    assign arith_cin = (op == 5'b00000) ? 1'b0 : 1'b1;
    adder_32bit u_ALU_adder(
        .a(a),
        .b(arith_b),
        .c_in(arith_cin),
        .result(arith_result),
        .c_out()   
     );
     
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
        case(op[4:2])
            3'b000: result = arith_result;
            3'b001: result = logic_result;
            3'b010: result = shift_result;
            3'b011: result = compare_result;
            default: result = 32'b0;
        endcase
    end         
endmodule
