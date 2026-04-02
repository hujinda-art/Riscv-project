`timescale 1ns / 1ps
`include "adder.v"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/14 10:56:38
// Design Name: 
// Module Name: cla_adder_32bit
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


module adder_32bit(
    input [31:0] a,b,
    input c_in,
    
    output [31:0] result,
    output c_out
    );
    wire [8:0] c_all;
    assign c_all[0] = c_in;
    
    genvar i;
    generate
        for(i = 0; i < 8; i = i + 1) begin:bit_all
            wire [3:0] a_4bit = a[(i*4)+3:i*4];
            wire [3:0] b_4bit = b[(i*4)+3:i*4];
            wire [3:0] s_4bit, p_4bit, g_4bit;
           
            
            adder_4bit u_cla(
                .a(a_4bit),
                .b(b_4bit),
                .c_in(c_all[i]),
                .c(),
                .c_out(c_all[i+1]),
                .s(s_4bit)
            );
            assign result[(i*4)+3:i*4] = s_4bit;
            end
    endgenerate
    assign c_out = c_all[8];
endmodule
