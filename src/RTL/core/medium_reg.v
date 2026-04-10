`timescale 1ns / 1ps
module medium_reg(
    input wire clk,
    input wire rst_n,
    input flush,
    input stall,

    input wire [31:0] imm_in,
    input wire        use_rs1,
    input wire        use_rs2,
    input wire        is_branch,
    input wire        is_jalr,
    input wire        is_load,
    input wire        is_store,
    input wire        reg_write_en,

    output reg  [31:0] imm_out,
    output reg        use_rs1_out,
    output reg        use_rs2_out,
    output reg        is_branch_out,
    output reg        is_jalr_out,
    output reg        is_load_out,
    output reg        is_store_out,
    output reg        reg_write_en_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imm_out <= 32'b0;
            use_rs1_out <= 1'b0;
            use_rs2_out <= 1'b0;
            is_branch_out <= 1'b0;
            is_jalr_out <= 1'b0;
            is_load_out <= 1'b0;
            is_store_out <= 1'b0;
            reg_write_en_out <= 1'b0;
        end else if (flush) begin
            imm_out <= 32'b0;
            use_rs1_out <= 1'b0;
            use_rs2_out <= 1'b0;
            is_branch_out <= 1'b0;
            is_jalr_out <= 1'b0;
            is_load_out <= 1'b0;
            is_store_out <= 1'b0;
            reg_write_en_out <= 1'b0;
        end else if (stall) begin
            imm_out <= imm_out;
            use_rs1_out <= use_rs1_out;
            use_rs2_out <= use_rs2_out;
            is_branch_out <= is_branch_out;
            is_jalr_out <= is_jalr_out;
            is_load_out <= is_load_out;
            is_store_out <= is_store_out;
            reg_write_en_out <= reg_write_en_out;
        end else begin
            imm_out <= imm_in;
            use_rs1_out <= use_rs1;
            use_rs2_out <= use_rs2;
            is_branch_out <= is_branch;
            is_jalr_out <= is_jalr;
            is_load_out <= is_load;
            is_store_out <= is_store;
            reg_write_en_out <= reg_write_en;
        end
    end
endmodule