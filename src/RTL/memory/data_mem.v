`timescale 1ns / 1ps
`include "../include/soc_config.vh"
//
// Data memory: BRAM-friendly, byte-write-enable, synchronous read.
// Ideal bus: ready always 1 (single-cycle access).
//
module data_mem #(
    parameter ADDR_WIDTH = `SOC_DMEM_ADDR_WIDTH
)(
    input  wire        clk,
    input  wire        valid,
    input  wire        read_en,
    input  wire        write_en,
    input  wire [1:0]  size,
    input  wire [31:0] address,
    input  wire [31:0] data_in,
    output reg  [31:0] data_out,
    output wire        ready
);

wire [ADDR_WIDTH-1:0] word_addr = address[ADDR_WIDTH+1:2];
wire [1:0] position = address[1:0];

(* ram_style = "block" *) reg [7:0] mem0 [0:((1 << ADDR_WIDTH) - 1)];
(* ram_style = "block" *) reg [7:0] mem1 [0:((1 << ADDR_WIDTH) - 1)];
(* ram_style = "block" *) reg [7:0] mem2 [0:((1 << ADDR_WIDTH) - 1)];
(* ram_style = "block" *) reg [7:0] mem3 [0:((1 << ADDR_WIDTH) - 1)];

// Byte write-enable generation
reg [3:0] byte_we;
reg [31:0] wdata_aligned;
reg ready_reg;
reg ready_reg_d1;
always @(*) begin
    byte_we       = 4'b0000;
    wdata_aligned = 32'b0;
    case (size)
        2'b00: begin // SB
            case (position)
                2'b00: begin byte_we = 4'b0001; wdata_aligned = {24'b0, data_in[7:0]}; end
                2'b01: begin byte_we = 4'b0010; wdata_aligned = {16'b0, data_in[7:0], 8'b0}; end
                2'b10: begin byte_we = 4'b0100; wdata_aligned = {8'b0,  data_in[7:0], 16'b0}; end
                2'b11: begin byte_we = 4'b1000; wdata_aligned = {data_in[7:0], 24'b0}; end
            endcase
        end
        2'b01: begin // SH
            case (position)
                2'b00: begin byte_we = 4'b0011; wdata_aligned = {16'b0, data_in[15:0]}; end
                2'b10: begin byte_we = 4'b1100; wdata_aligned = {data_in[15:0], 16'b0}; end
                default: begin byte_we = 4'b0000; wdata_aligned = 32'b0; end
            endcase
        end
        2'b10: begin // SW
            byte_we       = 4'b1111;
            wdata_aligned = data_in;
        end
        default: begin
            byte_we       = 4'b0000;
            wdata_aligned = 32'b0;
        end
    endcase
end

// Synchronous read + write
reg [31:0] mem_data;
reg [1:0]  size_q;
reg [1:0]  position_q;

always @(posedge clk) begin
    if (valid && read_en) begin
        mem_data   <= {mem3[word_addr], mem2[word_addr], mem1[word_addr], mem0[word_addr]};
        size_q     <= size;
        position_q <= position;
    end
    ready_reg <= valid? 1'b1 : 1'b0;
    if (write_en) begin
        if (byte_we[0]) mem0[word_addr] <= wdata_aligned[ 7: 0];
        if (byte_we[1]) mem1[word_addr] <= wdata_aligned[15: 8];
        if (byte_we[2]) mem2[word_addr] <= wdata_aligned[23:16];
        if (byte_we[3]) mem3[word_addr] <= wdata_aligned[31:24];
    end
end

// Read data sign-extension
always @(*) begin
    case (size_q)
        2'b00: begin
            case (position_q)
                2'b00: data_out = {{24{mem_data[ 7]}}, mem_data[ 7: 0]};
                2'b01: data_out = {{24{mem_data[15]}}, mem_data[15: 8]};
                2'b10: data_out = {{24{mem_data[23]}}, mem_data[23:16]};
                2'b11: data_out = {{24{mem_data[31]}}, mem_data[31:24]};
            endcase
        end
        2'b01: begin
            case (position_q)
                2'b00: data_out = {{16{mem_data[15]}}, mem_data[15:0]};
                2'b10: data_out = {{16{mem_data[31]}}, mem_data[31:16]};
                default: data_out = 32'h0;
            endcase
        end
        2'b10: data_out = mem_data;
        default: data_out = 32'h0;
    endcase
end

assign ready = ready_reg;

endmodule
