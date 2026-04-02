`timescale 1ns / 1ps
//
// EX/MEM 级间寄存器：锁存 EX 产生的访存相关信息与写回相关控制。
//
module EX_MEM_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire        ex_mem_read_en_in,
    input  wire        ex_mem_write_en_in,
    input  wire        ex_reg_write_en_in,
    input  wire [4:0]  ex_rd_in,
    input  wire [31:0] ex_alu_result_in,
    input  wire [31:0] ex_mem_addr_in,
    input  wire [31:0] ex_mem_wdata_in,
    output reg         mem_mem_read_en_out,
    output reg         mem_mem_write_en_out,
    output reg         mem_reg_write_en_out,
    output reg  [4:0] mem_rd_out,
    output reg  [31:0] mem_alu_result_out,
    output reg  [31:0] mem_mem_addr_out,
    output reg  [31:0] mem_mem_wdata_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_mem_read_en_out  <= 1'b0;
            mem_mem_write_en_out <= 1'b0;
            mem_reg_write_en_out <= 1'b0;
            mem_rd_out           <= 5'b0;
            mem_alu_result_out   <= 32'b0;
            mem_mem_addr_out     <= 32'b0;
            mem_mem_wdata_out    <= 32'b0;
        end else if (flush) begin
            mem_mem_read_en_out  <= 1'b0;
            mem_mem_write_en_out <= 1'b0;
            mem_reg_write_en_out <= 1'b0;
            mem_rd_out           <= 5'b0;
            mem_alu_result_out   <= 32'b0;
            mem_mem_addr_out     <= 32'b0;
            mem_mem_wdata_out    <= 32'b0;
        end else if (stall) begin
            // 保持不变
            mem_mem_read_en_out  <= mem_mem_read_en_out;
            mem_mem_write_en_out <= mem_mem_write_en_out;
            mem_reg_write_en_out <= mem_reg_write_en_out;
            mem_rd_out           <= mem_rd_out;
            mem_alu_result_out   <= mem_alu_result_out;
            mem_mem_addr_out     <= mem_mem_addr_out;
            mem_mem_wdata_out    <= mem_mem_wdata_out;
        end else begin
            mem_mem_read_en_out  <= ex_mem_read_en_in;
            mem_mem_write_en_out <= ex_mem_write_en_in;
            mem_reg_write_en_out <= ex_reg_write_en_in;
            mem_rd_out           <= ex_rd_in;
            mem_alu_result_out   <= ex_alu_result_in;
            mem_mem_addr_out     <= ex_mem_addr_in;
            mem_mem_wdata_out    <= ex_mem_wdata_in;
        end
    end

endmodule

