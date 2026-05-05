`timescale 1ns / 1ps
//
// uart_tx — 简单 UART 发送器 (8N1, 写触发)
// CLK_FREQ / BAUD_RATE 通过 parameter 配置
//
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  tx_data,
    input  wire        tx_start,   // 脉冲信号：拉高一个周期触发发送
    output wire        tx_busy,    // 1=正在发送，此时忽略 tx_start
    output reg         tx
);

    localparam BIT_CYCLES = CLK_FREQ / BAUD_RATE;        // 每位周期数
    localparam CNT_WIDTH  = $clog2(BIT_CYCLES) + 1;

    reg [3:0]  bit_idx;     // 当前正在发送的位 (0=start, 1..8=data, 9=stop)
    reg [CNT_WIDTH-1:0] cnt;
    reg        busy;
    reg [7:0]  data_buf;

    assign tx_busy = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;        // 空闲为高
            busy     <= 1'b0;
            bit_idx  <= 4'd0;
            cnt      <= 0;
            data_buf <= 8'h00;
        end else begin
            if (!busy && tx_start) begin
                busy     <= 1'b1;
                data_buf <= tx_data;
                bit_idx  <= 4'd0;
                cnt      <= 0;
            end else if (busy) begin
                if (cnt == BIT_CYCLES - 1) begin
                    cnt     <= 0;
                    bit_idx <= bit_idx + 4'd1;
                    case (bit_idx)
                        4'd0:    tx <= 1'b0;           // start bit
                        4'd1:    tx <= data_buf[0];
                        4'd2:    tx <= data_buf[1];
                        4'd3:    tx <= data_buf[2];
                        4'd4:    tx <= data_buf[3];
                        4'd5:    tx <= data_buf[4];
                        4'd6:    tx <= data_buf[5];
                        4'd7:    tx <= data_buf[6];
                        4'd8:    tx <= data_buf[7];
                        4'd9:    begin tx <= 1'b1; busy <= 1'b0; end
                        default: begin tx <= 1'b1; busy <= 1'b0; end
                    endcase
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end

endmodule
