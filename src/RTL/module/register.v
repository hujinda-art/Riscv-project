`timescale 1ns / 1ps
module reg_file_bram #(
    parameter REG_NUM = 32,            
    parameter REG_WIDTH = 32,            
    parameter ADDR_WIDTH = 5             
)(
    input wire clk,
    
    
    input wire we,                       
    input wire [ADDR_WIDTH-1:0] waddr,  
    input wire [REG_WIDTH-1:0] wdata,   
    
    
    input wire [ADDR_WIDTH-1:0] raddr1, 
    output reg [REG_WIDTH-1:0] rdata1,  
    
   
    input wire [ADDR_WIDTH-1:0] raddr2, 
    output reg [REG_WIDTH-1:0] rdata2   
);

// 使用真双端口Block RAM实现双读单写
(* ram_style = "block" *) reg [REG_WIDTH-1:0] regs [0:REG_NUM-1];

localparam ZERO_REG = 5'b00000;

integer i;
initial begin
    for (i = 0; i < REG_NUM; i = i + 1) begin
        regs[i] = {REG_WIDTH{1'b0}};
    end
end

// 写操作（同步）
always @(posedge clk) begin
    if (we && waddr != ZERO_REG) begin
        regs[waddr] <= wdata;
    end
end

// 读操作1（同步）
always @(posedge clk) begin
    if (raddr1 == 5'b0) begin
        rdata1 <= {REG_WIDTH{1'b0}};  
    end else if (we && (raddr1 == waddr)) begin
        rdata1 <= wdata;              // 前递：读取正在写入的数据
    end else begin
        rdata1 <= regs[raddr1];      
    end
end

// 读操作2
always @(posedge clk) begin
    if (raddr2 == 5'b0) begin
        rdata2 <= {REG_WIDTH{1'b0}};  
    end else if (we && (raddr2 == waddr)) begin
        rdata2 <= wdata;              
    end else begin
        rdata2 <= regs[raddr2];      
    end
end

endmodule