`timescale 1ns / 1ps
//
// Instruction memory: combinational read for IF alignment.
// Image: default is baked in via `include "inst_mem_program.vh" (synthesis-safe, no external .hex).
// Optional simulation overlay: parameter FILE + $readmemh only when not synthesizing.
//
module inst_mem #(
    parameter ADDR_WIDTH = 10,
    parameter FILE       = ""
)(
    input  wire [31:0] pc_addr,
    output wire [31:0] inst
);

(* ram_style = "distributed" *) reg [31:0] mem [0:((1<<ADDR_WIDTH)-1)];

wire [ADDR_WIDTH-1:0] word_addr = pc_addr[ADDR_WIDTH+1:2];

integer i;
initial begin
    for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
        mem[i] = 32'h00000013;   // NOP
    // Fixed program (same bits as program.hex words 0..31)
    `include "inst_mem_program.vh"
`ifndef SYNTHESIS
    if (FILE != "")
        $readmemh(FILE, mem);
`endif
end

assign inst = mem[word_addr];

endmodule
