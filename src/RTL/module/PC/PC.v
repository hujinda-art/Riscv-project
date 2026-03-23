`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/19 20:03:38
// Design Name: 
// Module Name: IF
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


module PC_unit#(
    parameter PC_RESET = 32'h0000_0000
)(
    input clk,
    input rst_n,
    
    input branch,
    input [31:0] pc_branch,
    
    input exception,
    input [31:0] pc_exception,
    
    input interrupt,
    input [31:0] pc_interrupt,
        
    output reg [31:0] pc_current,
    output reg [31:0] pc_plus_4
     );
     reg [31:0] pc_reg;
     reg [31:0] pc_next; 
    
    always @(*) begin
        if(exception) 
            pc_next = pc_exception;
        else if (interrupt)
            pc_next = pc_interrupt;
        else if (branch)
            pc_next = pc_branch;
        else
            pc_next = pc_current + 4;
     end       
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            pc_reg <= PC_RESET;
        else 
            pc_reg <= pc_next;       
    end
    
    always @(*) begin
        pc_current = pc_reg;
        pc_plus_4 = pc_reg + 4;
    end
endmodule
