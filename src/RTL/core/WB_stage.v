`timescale 1ns / 1ps
//
// WB 阶段：根据 MEM/WB 锁存的控制信号生成寄存器写回口。
//
module WB_stage (
    input  wire        wb_reg_write_en_in,
    input  wire        wb_is_load_in,
    input  wire [4:0]  wb_rd_in,
    input  wire [31:0] wb_alu_result_in,
    input  wire [31:0] wb_load_data_in,

    output wire        wb_we_out,
    output wire [4:0]  wb_waddr_out,
    output wire [31:0] wb_wdata_out
);
    assign wb_we_out     = wb_reg_write_en_in;
    assign wb_waddr_out = wb_rd_in;
    assign wb_wdata_out = wb_is_load_in ? wb_load_data_in : wb_alu_result_in;
endmodule

