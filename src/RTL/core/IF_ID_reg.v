`timescale 1ns / 1ps

module IF_ID_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] pc_current_in,
    input  wire [31:0] pc_plus_4_in,
    input  wire [31:0] instr_in,
    input  wire        instr_valid_in,
    output reg  [31:0] pc_current_out,
    output reg  [31:0] pc_plus_4_out,
    output reg  [31:0] instr_out,
    output reg         instr_valid_out
);

    localparam NOP = 32'h00000013;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_current_out  <= 32'h00000000;
            pc_plus_4_out   <= 32'h00000004;
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (flush) begin
            // flush 时向 ID 注入气泡
            instr_out       <= NOP;
            instr_valid_out <= 1'b0;
        end else if (stall) begin
            // stall 时保持级间寄存器不变
            pc_current_out  <= pc_current_out;
            pc_plus_4_out   <= pc_plus_4_out;
            instr_out       <= instr_out;
            instr_valid_out <= instr_valid_out;
        end else begin
            pc_current_out  <= pc_current_in;
            pc_plus_4_out   <= pc_plus_4_in;
            instr_out       <= instr_in;
            instr_valid_out <= instr_valid_in;
        end
    end

endmodule
