`timescale 1ns / 1ps
//
// 双写口寄存器堆：写口1 为正常 WB；写口2 为 IF/ID 提前 JAL 的链接写回（rd=PC+4）。
// 同拍同地址双写时，写口2 后执行，覆盖写口1（符合 JAL 晚于同拍 WB 的语义）。
//
module reg_file_bram #(
    parameter REG_NUM = 32,
    parameter REG_WIDTH = 32,
    parameter ADDR_WIDTH = 5
)(
    input wire clk,

    // 写口1：WB
    input wire we,
    input wire [ADDR_WIDTH-1:0] waddr,
    input wire [REG_WIDTH-1:0] wdata,

    // 写口2：JAL 链接（可与写口1 同拍）
    input wire we2,
    input wire [ADDR_WIDTH-1:0] waddr2,
    input wire [REG_WIDTH-1:0] wdata2,

    input wire [ADDR_WIDTH-1:0] raddr1,
    output reg [REG_WIDTH-1:0] rdata1,

    input wire [ADDR_WIDTH-1:0] raddr2,
    output reg [REG_WIDTH-1:0] rdata2
);

(* ram_style = "block" *) reg [REG_WIDTH-1:0] regs [0:REG_NUM-1];

localparam ZERO_REG = 5'b00000;

integer i;
initial begin
    for (i = 0; i < REG_NUM; i = i + 1) begin
        regs[i] = {REG_WIDTH{1'b0}};
    end
end

// 写操作：先写口1，再写口2（同地址时写口2 覆盖）
always @(posedge clk) begin
    if (we && (waddr != ZERO_REG))
        regs[waddr] <= wdata;
    if (we2 && (waddr2 != ZERO_REG))
        regs[waddr2] <= wdata2;
end

// 读口1：同拍前递，写口2 优先于写口1
always @(posedge clk) begin
    if (raddr1 == ZERO_REG) begin
        rdata1 <= {REG_WIDTH{1'b0}};
    end else if (we2 && (waddr2 != ZERO_REG) && (raddr1 == waddr2)) begin
        rdata1 <= wdata2;
    end else if (we && (waddr != ZERO_REG) && (raddr1 == waddr)) begin
        rdata1 <= wdata;
    end else begin
        rdata1 <= regs[raddr1];
    end
end

// 读口2
always @(posedge clk) begin
    if (raddr2 == ZERO_REG) begin
        rdata2 <= {REG_WIDTH{1'b0}};
    end else if (we2 && (waddr2 != ZERO_REG) && (raddr2 == waddr2)) begin
        rdata2 <= wdata2;
    end else if (we && (waddr != ZERO_REG) && (raddr2 == waddr)) begin
        rdata2 <= wdata;
    end else begin
        rdata2 <= regs[raddr2];
    end
end

endmodule
