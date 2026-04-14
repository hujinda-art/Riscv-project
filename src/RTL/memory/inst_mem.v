`timescale 1ns / 1ps
`include "../include/soc_config.vh"
//
// Instruction memory (ROM-like):
// - Combinational read: inst = mem[word_addr], ready always 1.
// - Image: baked in via `include "inst_mem_program.vh".
// - Optional simulation overlay: FILE + $readmemh (non-synthesis).
//
module inst_mem #(
    parameter ADDR_WIDTH = `SOC_IMEM_ADDR_WIDTH,
    parameter FILE       = ""
)(
    input  wire        clk,
    input  wire        req,
    input  wire [31:0] pc_addr,
    output wire [31:0] inst,
    output wire        ready
);

(* ram_style = "distributed" *) reg [31:0] mem [0:((1<<ADDR_WIDTH)-1)];

wire [ADDR_WIDTH-1:0] word_addr = pc_addr[ADDR_WIDTH+1:2];

integer i;
initial begin
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
        mem[i] = 32'h00000013;   // NOP
    `include "inst_mem_program.vh"
`ifndef SYNTHESIS
    if (FILE != "")
        $readmemh(FILE, mem);
`endif
end

assign inst  = mem[word_addr];
assign ready = 1'b1;

endmodule
