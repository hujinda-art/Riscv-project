`timescale 1ns / 1ps
module EX_WB_reg(
    input wire        clk,
    input wire        rst_n,
    input wire        stall,
    input wire        flush,
    input wire [31:0] ex_result,
    input wire [4:0]  ex_rd,
    input wire        ex_reg_write_en,
    input wire        load_occupation,    
    output reg  [31:0] wb_result,
    output reg  [4:0]  wb_rd,
    output reg        wb_reg_write_en
);

wire stall_final;
assign stall_final = stall & load_occupation;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wb_result <= 32'b0;
        wb_rd <= 5'b0;
        wb_reg_write_en <= 1'b0;
    end else if (flush) begin
        wb_result <= 32'b0;
        wb_rd <= 5'b0;
        wb_reg_write_en <= 1'b0;
    end else if (stall_final) begin
        wb_result <= wb_result;
        wb_rd <= wb_rd;
        wb_reg_write_en <= wb_reg_write_en;
    end else begin
        wb_result <= ex_result;
        wb_rd <= ex_rd;
        wb_reg_write_en <= ex_reg_write_en;
    end
end
endmodule