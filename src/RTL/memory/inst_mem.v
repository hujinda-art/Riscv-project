`timescale 1ns /1ps;
module inst_mem #(
    parameter ADDR_WIDTH = 10,
    // 空字符串：仿真由 testbench 层次路径写 mem；非空则 $readmemh 加载。
    parameter FILE = ""
)(
    input wire [31:0] pc_addr,      
    output wire [31:0] inst          
);


(*ram_style = "block"*)reg [31:0] mem [0:1023];

wire [ADDR_WIDTH-1:0] word_addr = pc_addr[ADDR_WIDTH+1:2];


initial begin
    for(integer i = 0; i < (1<<ADDR_WIDTH); i = i+1)  
            mem[i] = 32'h00000013;
    if (FILE != "")
        $readmemh(FILE, mem);
end

// 组合读：与 IF 阶段同一周期内 imem_addr -> imem_data，便于流水线对齐
assign inst = mem[word_addr];

endmodule