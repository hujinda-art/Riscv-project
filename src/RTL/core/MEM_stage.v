`timescale 1ns / 1ps
//
// MEM 阶段：数据总线接口占位。
// 实际存储器已移至 soc_top 层，此处仅将 soc_top 侧读数据透传给 MEM/WB 寄存器。
// clk/rst_n 保留供后续扩展（cache、MMU 等）使用。
//
module MEM_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] dmem_rdata_in,  // 来自 soc_top 侧存储器的读数据
    output wire [31:0] mem_rdata       // 送往 MEM/WB 寄存器
);
    assign mem_rdata = dmem_rdata_in;
endmodule
