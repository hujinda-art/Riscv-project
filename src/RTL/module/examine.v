`timescale 1ns / 1ps
module examine(
    input wire [31:0] signal_in,
    output wire [31:0] signal_out
);

// Keep this module as a simple passthrough probe point.
assign signal_out = signal_in;

endmodule