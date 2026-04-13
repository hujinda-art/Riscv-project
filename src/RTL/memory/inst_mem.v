`timescale 1ns / 1ps
`include "../include/soc_config.vh"
//
// Instruction memory (ROM-like, BRAM friendly):
// - Synchronous read with req/ready handshake.
// - One request takes one wait cycle, then ready=1 for one cycle.
// - Data is prepared one cycle before ready so IF/ID can sample it reliably.
// - Image: default is baked in via `include "inst_mem_program.vh".
// - Optional simulation overlay: FILE + $readmemh only when not synthesizing.
//
module inst_mem #(
    parameter ADDR_WIDTH = `SOC_IMEM_ADDR_WIDTH,
    parameter FILE       = ""
)(
    input  wire        clk,
    input  wire        req,
    input  wire [31:0] pc_addr,
    output reg  [31:0] inst,
    output reg         ready
);

(* ram_style = "block", rom_style = "block" *) reg [31:0] mem [0:((1<<ADDR_WIDTH)-1)];

wire [ADDR_WIDTH-1:0] word_addr = pc_addr[ADDR_WIDTH+1:2];
reg                   pending;

integer i;
initial begin
    inst    = 32'h00000013;
    ready   = 1'b0;
    pending = 1'b0;
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
        mem[i] = 32'h00000013;   // NOP
    // Fixed program (same bits as program.hex words 0..31)
    `include "inst_mem_program.vh"
`ifndef SYNTHESIS
    if (FILE != "")
        $readmemh(FILE, mem);
`endif
end

always @(posedge clk) begin
    ready <= 1'b0;
    if (pending) begin
        ready   <= 1'b1;
        pending <= 1'b0;
    end

    if (req && !pending) begin
        // Read data one cycle earlier than ready pulse.
        inst        <= mem[word_addr];
        pending     <= 1'b1;
    end
end

endmodule
