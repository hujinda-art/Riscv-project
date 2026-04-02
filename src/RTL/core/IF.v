`timescale 1ns / 1ps
`include "../module/PC/PC.v"
`include "../memory/inst_mem.v"
module IF_stage (
    input wire clk,
    input wire rst_n,
    

    // 仅结构冒险类停顿：冻结 PC 与 IF 输出；JAL 提前跳转用的 IF/ID 单独停顿不要接这里。
    input wire stall_pc,
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
    
    // 本拍取指地址上下文（来自 PC 寄存器），供 IF/ID 锁存；不用于驱动 PC。
    output wire [31:0] if_pc,
    output wire [31:0] if_pc_plus4,
    output wire [31:0] instr_out,
    output wire        instr_valid_out
);
    localparam NOP = 32'h00000013;

    wire [31:0] pc_current;
    wire [31:0] pc_plus_4;
    
    
    wire [31:0] imem_addr;
    wire [31:0] imem_data;
    inst_mem u_inst_mem (
        .pc_addr(imem_addr),
        .inst(imem_data)
    );

    PC_unit pc_unit_inst (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_pc),
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
        .predict(1'b0),
        .pc_predict(32'b0),
        .pc_current(pc_current),   
        .pc_plus_4(pc_plus_4)      
    );
    
    assign imem_addr = pc_current;
    
    
    wire instr_invalid = (flush || stall_pc);
    
    assign instr_out = instr_invalid ? NOP : imem_data;
    assign if_pc       = pc_current;
    assign if_pc_plus4 = pc_plus_4;
    assign instr_valid_out = ~instr_invalid;
    
    
    
endmodule