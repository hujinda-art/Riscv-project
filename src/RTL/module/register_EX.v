`timescale 1ns / 1ps
module register_EX(
    input wire clk,
    input wire rst_n,
    input wire stall,
    input wire flush,
    input wire load_enable,
    input wire load_success,
    input wire [4:0] rd_in,
    input wire [31:0] rd_ex_result_in,
    input wire [31:0] rd_mem_rdata_in,
    output wire [4:0] rd_out,
    output wire [31:0] rd_data_out,
    output wire [4:0] rd_out2,
    output wire [31:0] rd_data_out2,
    output wire [4:0] rd_reg_load_out,
    output wire [31:0] rd_data_reg_load_out,
    output wire load_lock_out
);
    parameter   NOP_REG = 5'b00000;
    parameter   NOP_DATA = 32'h00000000;

    // --- 第 1 级（1 条前）---
    reg [4:0] rd_reg;
    reg [31:0] rd_data_reg;
    // --- 第 2 级（2 条前）---
    reg [4:0] rd_reg2;
    reg [31:0] rd_data_reg2;

    reg [4:0] rd_reg_load;
    reg [31:0] rd_data_reg_load;
    reg load_lock;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_lock <= 1'b0;
        end else if (flush) begin
            load_lock <= 1'b0;
        end else if (load_success) begin
            load_lock <= 1'b0;
        end else if (load_enable) begin
            load_lock <= 1'b1;
        end else begin
            load_lock <= load_lock;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg_load <= NOP_REG;
            rd_data_reg_load <= NOP_DATA;
        end else if (flush) begin
            rd_reg_load <= NOP_REG;
            rd_data_reg_load <= NOP_DATA;
        end else if (load_success) begin
            rd_data_reg_load <= rd_mem_rdata_in;
        end else if (load_enable) begin
            rd_reg_load  <= rd_in;
            rd_data_reg_load <= rd_ex_result_in;
        end else begin
            rd_reg_load <= rd_reg_load;
            rd_data_reg_load <= rd_data_reg_load;
        end
    end

    // ALU 前递：2 级 shift register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg  <= 5'b0;  rd_data_reg  <= 32'b0;
            rd_reg2 <= 5'b0;  rd_data_reg2 <= 32'b0;
        end else if (flush) begin
            rd_reg  <= 5'b0;  rd_data_reg  <= 32'b0;
            rd_reg2 <= 5'b0;  rd_data_reg2 <= 32'b0;
        end else if (stall) begin
            rd_reg  <= rd_reg;  rd_data_reg  <= rd_data_reg;
            rd_reg2 <= rd_reg2; rd_data_reg2 <= rd_data_reg2;
        end else if (!load_enable) begin
            rd_reg2 <= rd_reg;           rd_data_reg2 <= rd_data_reg;
            rd_reg  <= rd_in;            rd_data_reg  <= rd_ex_result_in;
        end else begin
            rd_reg2 <= rd_reg;           rd_data_reg2 <= rd_data_reg;
            rd_reg  <= rd_reg;           rd_data_reg  <= rd_data_reg;
        end
    end

    assign rd_out      = rd_reg;
    assign rd_data_out = rd_data_reg;
    assign rd_out2      = rd_reg2;
    assign rd_data_out2 = rd_data_reg2;
    assign rd_reg_load_out = rd_reg_load;
    assign rd_data_reg_load_out = rd_data_reg_load;
    assign load_lock_out = load_lock;
endmodule
