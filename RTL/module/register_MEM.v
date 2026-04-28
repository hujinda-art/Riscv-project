`timescale 1ns / 1ps
module register_MEM(
    input wire clk,
    input wire rst_n,
    input wire flush,
    input wire load_success,
    output wire load_status_out
);
    reg load_status_1;
    reg load_status_2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_status_1 <= 1'b0;
            load_status_2 <= 1'b0;
        end else if (flush) begin
            load_status_1 <= 1'b0;
            load_status_2 <= 1'b0;
        end else begin
            load_status_1 <= load_success;
            load_status_2 <= load_status_1;
        end
    end
    assign load_status_out = load_status_2;
endmodule