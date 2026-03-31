`timescale 1ns /1ps;
module inst_mem #(
    parameter ADDR_WIDTH = 10,
    parameter FILE = "program.hex"    
)(
    input wire clk,
    input wire [31:0] pc_addr,      
    output reg [31:0] inst          
);


(*ram_style = "block"*)reg [31:0] mem [0:1023];


initial begin
    if(FILE != "")
        $readmemh("program.hex", mem);
    else begin
        for(integer i = 0; i < (1<<ADDR_WIDTH); i = i+1)  
            mem[i] = 32'h00000013;
    end 
end

// 同步读取
always @(posedge clk) begin
        inst <= mem[pc_addr[11:2]];
end

endmodule