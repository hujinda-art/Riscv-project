`timescale 1ns / 1ps
//
// Register file: single write port (we2/JAL > we/WB priority), BRAM-friendly.
//
// Priority rule (same as before):
//   we2 (JAL link) > we (WB)
//   Same address: we2 wins, we dropped.
//   Different address: we2 takes this cycle, we is buffered one cycle.
//
// BRAM inference strategy:
//   - Pure synchronous read: rdata <= regs[raddr] (no condition inside).
//   - Forwarding done externally: bypass register captures last write,
//     output mux selects bypass when raddr_q == waddr of previous cycle.
//   - x0 forced to zero externally.
//
module reg_file_bram #(
    parameter REG_NUM    = 32,
    parameter REG_WIDTH  = 32,
    parameter ADDR_WIDTH = 5
)(
    input  wire                   clk,

    // Write port 1: WB stage
    input  wire                   we,
    input  wire [ADDR_WIDTH-1:0]  waddr,
    input  wire [REG_WIDTH-1:0]   wdata,

    // Write port 2: JAL link (ID stage), higher priority
    input  wire                   we2,
    input  wire [ADDR_WIDTH-1:0]  waddr2,
    input  wire [REG_WIDTH-1:0]   wdata2,

    // Read ports (synchronous, 1 cycle latency)
    input  wire [ADDR_WIDTH-1:0]  raddr1,
    output wire [REG_WIDTH-1:0]   rdata1,
    input  wire [ADDR_WIDTH-1:0]  raddr2,
    output wire [REG_WIDTH-1:0]   rdata2
);

localparam ZERO = {ADDR_WIDTH{1'b0}};

// ----------------------------------------------------------------
// Write arbiter: we2 > we
// When both active to different addresses: we2 wins this cycle,
// we is buffered and committed next cycle.
// JAL flushes the pipeline (min ~2 cycle gap between JALs) so
// the buffer never overflows in a legal instruction stream.
// ----------------------------------------------------------------
reg                  we_buf;
reg [ADDR_WIDTH-1:0] waddr_buf;
reg [REG_WIDTH-1:0]  wdata_buf;

// This cycle's effective write (combinational)
wire        we_eff    = we2 ? 1'b1     : we_buf ? 1'b1     : we;
wire [ADDR_WIDTH-1:0] waddr_eff = we2  ? waddr2  : we_buf  ? waddr_buf : waddr;
wire [REG_WIDTH-1:0]  wdata_eff = we2  ? wdata2  : we_buf  ? wdata_buf : wdata;
wire we_final = we_eff && (waddr_eff != ZERO);

// Buffer WB write when preempted by we2 to a different address
always @(posedge clk) begin
    if (we2 && we && (waddr != ZERO) && (waddr != waddr2)) begin
        we_buf    <= 1'b1;
        waddr_buf <= waddr;
        wdata_buf <= wdata;
    end else begin
        we_buf    <= 1'b0;
        waddr_buf <= {ADDR_WIDTH{1'b0}};
        wdata_buf <= {REG_WIDTH{1'b0}};
    end
end

// ----------------------------------------------------------------
// BRAM storage: pure synchronous read/write
// ----------------------------------------------------------------
(* ram_style = "block" *) reg [REG_WIDTH-1:0] regs [0:REG_NUM-1];

integer k;
initial begin
    for (k = 0; k < REG_NUM; k = k + 1)
        regs[k] = {REG_WIDTH{1'b0}};
end

reg [REG_WIDTH-1:0] rdata1_raw;
reg [REG_WIDTH-1:0] rdata2_raw;

always @(posedge clk) begin
    if (we_final)
        regs[waddr_eff] <= wdata_eff;
    rdata1_raw <= regs[raddr1];
    rdata2_raw <= regs[raddr2];
end

// ----------------------------------------------------------------
// External bypass: forward write to read when same address
// (handles read-after-write in the same clock edge)
// ----------------------------------------------------------------
reg                  bypass_valid;
reg [ADDR_WIDTH-1:0] bypass_addr;
reg [REG_WIDTH-1:0]  bypass_data;
reg [ADDR_WIDTH-1:0] raddr1_q;
reg [ADDR_WIDTH-1:0] raddr2_q;

always @(posedge clk) begin
    bypass_valid <= we_final;
    bypass_addr  <= waddr_eff;
    bypass_data  <= wdata_eff;
    raddr1_q     <= raddr1;
    raddr2_q     <= raddr2;
end

wire hit1 = bypass_valid && (bypass_addr == raddr1_q);
wire hit2 = bypass_valid && (bypass_addr == raddr2_q);

// x0 always zero; use bypass when write-read collision
assign rdata1 = (raddr1_q == ZERO) ? {REG_WIDTH{1'b0}} :
                hit1               ? bypass_data        : rdata1_raw;
assign rdata2 = (raddr2_q == ZERO) ? {REG_WIDTH{1'b0}} :
                hit2               ? bypass_data        : rdata2_raw;

endmodule
