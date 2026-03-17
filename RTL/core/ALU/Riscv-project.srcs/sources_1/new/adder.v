`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/13 19:57:02
// Design Name: 
// Module Name: adder
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


module adder_4bit(
    input [3:0] a,b,
    input c_in,
    output [3:0] c,
    output c_out,
    output [3:0] s
    );
    wire [3:0] c;
    wire [3:0] g,p;//carry-over to possess less time
    assign g = a & b;
    assign p = a ^ b;
    assign c[0] = g[0] | (p[0] & c_in);
    assign c[1] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c_in);
    assign c[2] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | 
                     (p[2] & p[1] & p[0] & c_in);
    assign c[3] = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | 
                     (p[3] & p[2] & p[1] & g[0]) | 
                     (p[3] & p[2] & p[1] & p[0] & c_in); 
    
    assign s[0] = a[0] ^ b[0] ^ c_in;//less area
    assign s[1] = a[1] ^ b[1] ^ c[0];
    assign s[2] = a[2] ^ b[2] ^ c[1];
    assign s[3] = a[3] ^ b[3] ^ c[2];
    assign c_out = c[3];
endmodule
