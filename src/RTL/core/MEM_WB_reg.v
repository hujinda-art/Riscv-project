`timescale 1ns / 1ps
//
// MEM/WB 级间寄存器：锁存 MEM 阶段结果与写回控制。
//
module MEM_WB_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire        mem_reg_write_en_in,
    input  wire        mem_is_load_in,
    input  wire [4:0]  mem_rd_in,
    input  wire [31:0] mem_alu_result_in,
    input  wire [31:0] mem_load_data_in,
    output reg         wb_reg_write_en_out,
    output reg         wb_is_load_out,
    output reg  [4:0] wb_rd_out,
    output reg  [31:0] wb_alu_result_out,
    output reg  [31:0] wb_load_data_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_reg_write_en_out <= 1'b0;
            wb_is_load_out      <= 1'b0;
            wb_rd_out           <= 5'b0;
            wb_alu_result_out  <= 32'b0;
            wb_load_data_out   <= 32'b0;
        end else if (flush) begin
            wb_reg_write_en_out <= 1'b0;
            wb_is_load_out      <= 1'b0;
            wb_rd_out           <= 5'b0;
            wb_alu_result_out  <= 32'b0;
            wb_load_data_out   <= 32'b0;
        end else if (stall) begin
            wb_reg_write_en_out <= wb_reg_write_en_out;
            wb_is_load_out      <= wb_is_load_out;
            wb_rd_out           <= wb_rd_out;
            wb_alu_result_out  <= wb_alu_result_out;
            wb_load_data_out   <= wb_load_data_out;
        end else begin
            wb_reg_write_en_out <= mem_reg_write_en_in;
            wb_is_load_out      <= mem_is_load_in;
            wb_rd_out           <= mem_rd_in;
            wb_alu_result_out  <= mem_alu_result_in;
            wb_load_data_out   <= mem_load_data_in;
        end
    end

endmodule

