`timescale 1ns / 1ps
`include "PC.v"
module IF_stage (
    input wire clk,
    input wire rst_n,
    

    input wire stall,         
    input wire flush, //冲刷IF_ID register     
    
    input wire exception,
    input wire [31:0] pc_exception,
    
    input wire interrupt,
    input wire [31:0] pc_interrupt,
    
    input wire jalr,            
    input wire [31:0] pc_jalr,
    
    input wire jump,            
    input wire [31:0] pc_jump,
    
    input wire branch,          
    input wire [31:0] pc_branch,
    
    output wire [31:0] imem_addr,    
    input wire [31:0] imem_data,     
    
    output wire [31:0] pc_current_out,   
    output wire [31:0] pc_plus_4_out,    
    output wire [31:0] instr_out,        
    output wire instr_valid_out          
);
    
    wire [31:0] pc_current;
    wire [31:0] pc_plus_4;
    
    PC_unit pc_unit_inst (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),           
        .exception(exception),
        .pc_exception(pc_exception),
        .interrupt(interrupt),
        .pc_interrupt(pc_interrupt),
        .jalr(jalr),
        .pc_jalr(pc_jalr),
        .jump(jump),
        .pc_jump(pc_jump),
        .branch(branch),
        .pc_branch(pc_branch),
        .pc_current(pc_current),   
        .pc_plus_4(pc_plus_4)      
    );
    
    assign imem_addr = pc_current;
    
    
    wire instr_invalid = (flush || stall);
    
    assign instr_out = instr_invalid ? 32'h00000013 : imem_data;
    assign pc_current_out = pc_current;
    assign pc_plus_4_out = pc_plus_4;
    assign instr_valid_out = ~instr_invalid;
    
    
    
endmodule