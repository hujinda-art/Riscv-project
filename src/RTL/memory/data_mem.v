`timescale 1ns / 1ps
`include "../include/soc_config.vh"
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
    output reg         ready
);

(* ram_style = "block" *) reg [31:0] mem [0:((1 << ADDR_WIDTH) - 1)];

wire [ADDR_WIDTH-1:0] word_addr = address[ADDR_WIDTH+1:2];
wire [1:0] position = address[1:0];
reg [31:0] wmask;
reg [31:0] wdata;
reg [31:0] mem_data;
reg [1:0]  size_q;
reg [1:0]  position_q;
reg        pending;

initial begin
    mem_data   = 32'b0;
    size_q     = `SOC_MEM_SIZE_WORD;
    position_q = 2'b00;
    ready      = 1'b0;
    pending    = 1'b0;
end

always @(*) begin
    case(size)
        2'b00:begin
            case(position)
                2'b00:begin
                    wmask = 32'h000000FF;
                    wdata = {24'b0, data_in[7:0]};
                end
                2'b01:begin
                    wmask = 32'h0000FF00;
                    wdata = {16'b0, data_in[7:0], 8'b0};
                end
                2'b10:begin
                    wmask = 32'h00FF0000;
                    wdata = {8'b0, data_in[7:0], 16'b0};
                end
                2'b11:begin
                    wmask = 32'hFF000000;
                    wdata = {data_in[7:0], 24'b0};
                end
            endcase
        end
        2'b01:begin
            case(position)
                2'b00:begin
                    wmask = 32'h0000FFFF;
                    wdata = {16'b0, data_in[15:0]};
                end
                2'b01:begin
                    wmask = 32'hFFFF0000;
                    wdata = {data_in[15:0], 16'b0};
                end
                default:begin   
                    wmask = 32'h0;
                    wdata = 32'h0;
               end
            endcase
        end
        2'b10:begin
            wmask = 32'hFFFFFFFF;
            wdata = data_in[31:0];
        end
        default:begin
            wmask = 32'h0;
            wdata = 32'h0;
        end
    endcase
end

always @(posedge clk) begin
    ready <= 1'b0;

    // Respond one cycle after request acceptance.
    if (pending) begin
        ready   <= 1'b1;
        pending <= 1'b0;
    end

    if (valid && !pending) begin
        size_q     <= size;
        position_q <= position;
        if (read_en)
            mem_data <= mem[word_addr];
        if (write_en)
            mem[word_addr] <= (mem[word_addr] & ~wmask) | wdata;
        pending <= 1'b1;
    end
end

always@(*) begin
    case(size_q)
        2'b00:begin
            case(position_q)
                2'b00:data_out = {{24{mem_data[7]}},mem_data[7:0]};
                2'b01:data_out = {{24{mem_data[15]}},mem_data[15:8]};
                2'b10:data_out = {{24{mem_data[23]}},mem_data[23:16]};
                2'b11:data_out = {{24{mem_data[31]}},mem_data[31:24]};
            endcase
        end
        2'b01:begin
            case(position_q)
                2'b00:data_out = {{16{mem_data[15]}},mem_data[15:0]};
                2'b01:data_out = {{16{mem_data[31]}},mem_data[31:16]};
                default:data_out = 32'h0;
            endcase
        end
        2'b10:begin
            data_out = mem_data;
        end
        default: data_out = 32'h0;
            
    endcase
end            
            
endmodule