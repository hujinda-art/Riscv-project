`timescale 1ns /1ps;
module inst_mem (
    input wire clk,
    input wire rst_n,
    input wire [31:0] pc_addr,      
    output reg [31:0] inst          
);


reg [31:0] mem [0:1023];


initial begin
    $readmemh("program.hex", mem);  
end

// 同步读取
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        inst <= 32'h00000013;  
    end else begin
        inst <= mem[pc_addr[11:2]];
    end
end

endmodule