`timescale 1ns / 1ps
`include "../module/PC/PC.v"
module IF_stage (
    input wire clk,
    input wire rst_n,

    // 仅结构冒险类停顿：冻结 PC 与 IF 输出。
    input wire stall_pc,
    input wire flush,

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

    // 取指上下文，供 IF/ID 锁存
    output wire [31:0] if_pc,
    output wire [31:0] if_pc_plus4,

    // 指令存储器总线（由 soc_top 层连接实际存储器）
    output wire [31:0] imem_addr,   // 取指地址，等于 pc_current
    output wire        imem_req,    // 取指请求有效（非停顿时为 1）
    input  wire [31:0] imem_rdata,  // 来自外部存储器的指令数据
    input  wire        imem_ready,  // 存储器侧数据就绪（握手 ready）

    output wire [31:0] instr_out,
    output wire        instr_valid_out
);
    localparam NOP = 32'h00000013;

    wire [31:0] pc_current;
    wire [31:0] pc_plus_4;

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
    assign imem_req  = ~stall_pc;   // 未停顿时持续请求新指令

    wire instr_invalid = (flush || stall_pc);

    assign instr_out       = instr_invalid ? NOP : imem_rdata;
    assign if_pc           = pc_current;
    assign if_pc_plus4     = pc_plus_4;
    // imem_ready=0 时指令无效。
    assign instr_valid_out = ~instr_invalid & imem_ready;

endmodule
