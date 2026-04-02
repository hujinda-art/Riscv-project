`timescale 1ns /1ps;
module inst_mem #(
    parameter ADDR_WIDTH = 10,
    parameter FILE = "program.hex"    
)(
    input wire [31:0] pc_addr,      
    output wire [31:0] inst          
);


(*ram_style = "block"*)reg [31:0] mem [0:1023];

wire [ADDR_WIDTH-1:0] word_addr = pc_addr[ADDR_WIDTH+1:2];

initial begin
    if(FILE != "")
        $readmemh("program.hex", mem);
    else begin
        for(integer i = 0; i < (1<<ADDR_WIDTH); i = i+1)  
            mem[i] = 32'h00000013;
    end 
end

// 组合读：与 IF 阶段同一周期内 imem_addr -> imem_data，便于流水线对齐
assign inst = mem[word_addr];

endmodule