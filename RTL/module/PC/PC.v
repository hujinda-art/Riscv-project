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


module PC_unit #(
    parameter PC_RESET = 32'h0000_0000
)(
    input wire clk,
    input wire rst_n,
    
    
    input wire stall,           // Pause
    
    input wire exception,       // 异常
    input wire [31:0] pc_exception,
    
    input wire interrupt,       // 中断
    input wire [31:0] pc_interrupt,
    
    input wire jalr,            
    input wire [31:0] pc_jalr,
    
    input wire jump,            
    input wire [31:0] pc_jump,
    
    input wire branch,          
    input wire [31:0] pc_branch,
    
    // 分支预测
    input wire predict,   
    input wire [31:0] pc_predict,
    
    
    output reg [31:0] pc_current,
    output reg [31:0] pc_plus_4
);
    
    reg [31:0] pc_reg;
    wire [31:0] pc_next;
    
    
    assign pc_next = 
        (!rst_n)           ? PC_RESET :           
        (exception)        ? pc_exception :      
        (interrupt)        ? pc_interrupt :      
        (jalr)             ? pc_jalr :           
        (jump)             ? pc_jump :           
        (branch)           ? pc_branch :         
        (predict)          ? pc_predict :        
        (stall)            ? pc_reg :            
                             pc_reg + 32'd4;     
    
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= PC_RESET;
        end
        else begin
            pc_reg <= pc_next;
        end
    end
    
    always @(*) begin
        pc_current = pc_reg;
        pc_plus_4 = pc_reg + 32'd4;
    end
    
endmodule