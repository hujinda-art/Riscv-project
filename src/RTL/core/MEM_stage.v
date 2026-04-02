`timescale 1ns / 1ps
//
// MEM 阶段：对接数据存储器 data_mem.v
//
`include "../memory/data_mem.v"
module MEM_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_write_en,
    input  wire [1:0]  mem_size,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    output wire [31:0] mem_rdata
);
    data_mem u_data_mem (
        .clk(clk),
        .write_en(mem_write_en),
        .size(mem_size),
        .address(mem_addr),
        .data_in(mem_wdata),
        .data_out(mem_rdata)
    );
endmodule

