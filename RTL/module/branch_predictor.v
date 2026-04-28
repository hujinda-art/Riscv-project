`timescale 1ns / 1ps

module branch_predictor (
    input  wire clk,
    input  wire rst_n,
    input  wire branch_resolved,
    input  wire branch_taken,
    output wire predict_taken
);

    reg [1:0] counter;

    assign predict_taken = counter[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 2'b01; // weakly not taken
        end else if (branch_resolved) begin
            if (branch_taken && (counter != 2'b11)) begin
                counter <= counter + 2'b01;
            end else if (!branch_taken && (counter != 2'b00)) begin
                counter <= counter - 2'b01;
            end
        end
    end

endmodule
