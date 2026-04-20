`timescale 1ns / 1ps
// 16 位 LFSR（右移，反馈进 bit15），周期 2^16-1（全 0 为非法态，复位勿给 16'h0000）
module lfsr16_data (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       advance,   // 仅在 miss 要选人时步进，每拍不步进
    output wire [15:0] state     // 需要随机位时直接接 state
);
    reg [15:0] lfsr;

    // 反馈 = bit0 ^ bit2 ^ bit3 ^ bit5
    wire fb = ^{lfsr[0], lfsr[2], lfsr[3], lfsr[5]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hACE1;          // 任意非 0 种子即可
        else if (advance)
            lfsr <= {fb, lfsr[15:1]};
    end

    assign state = lfsr;
endmodule