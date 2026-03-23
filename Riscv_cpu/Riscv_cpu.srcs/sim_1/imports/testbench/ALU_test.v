`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/14 15:06:28
// Design Name: 
// Module Name: ALU_test
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////




module tb_ALU;
    
    reg  clk;
    reg  [31:0] a, b;
    reg  [4:0]  op;
    wire [31:0] result;
    wire        condition;
    
    integer error_count = 0;
    integer test_count = 0;
    
    ALU u_alu(
        .a(a),
        .b(b),
        .op(op),
        .result(result),
        .condition(condition)
    );
    
    
    initial begin
        #20;
        
        // 算术运算测试
        test_one(5'b00000, 32'd5, 32'd3, 32'd8, 1'bx, "5+3=8");
        test_one(5'b00001, 32'd10, 32'd4, 32'd6, 1'bx, "10-4=6");
        
        // 逻辑运算测试
        test_one(5'b00100, 32'hF0F0F0F0, 32'h0F0F0F0F, 32'h00000000, 1'bx, "AND");
        test_one(5'b00101, 32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF, 1'bx, "OR");
        test_one(5'b00110, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF, 1'bx, "XOR");
        
        // 移位运算测试
        test_one(5'b01000, 32'h0000000F, 32'd4, 32'h000000F0, 1'bx, "SLL");
        test_one(5'b01001, 32'h000000F0, 32'd4, 32'h0000000F, 1'bx, "SRL");
        test_one(5'b01010, 32'h80000000, 32'd1, 32'hC0000000, 1'bx, "SRA");
        
        // 比较运算测试
        test_one(5'b10000, 32'd5, 32'd5, 32'bx, 1'b1, "EQ");
        test_one(5'b10001, 32'd5, 32'd3, 32'bx, 1'b1, "NE");
        test_one(5'b10010, 32'd5, 32'd10, 32'bx, 1'b1, "ULT");
        ///test_one(5'b10110, 32'hFFFFFFFB, 32'hFFFFFFFD, 32'bx, 1'b1, "SLT");
        
        // 边界测试
        test_one(5'b00000, 32'hFFFFFFFF, 32'd1, 32'd0, 1'bx, "overflow");
        ///test_one(5'b01000, 32'h00000001, 32'd32, 32'h00000000, 1'bx, "SLL by 32");
        
        $display("\nTotal tests: %0d", test_count);
        $display("Errors:      %0d", error_count);
        
        if(error_count == 0)
            $display("PASS");
        else
            $display("FAIL");
        
        #100;
        $stop;
    end
    
    task test_one;
        input [4:0]  op_in;
        input [31:0] a_in, b_in, exp_result;
        input        exp_cond;
        input [79:0] desc;
        
        reg [31:0] exp_res;
        reg        exp_cnd;
    begin
        a = a_in;
        b = b_in;
        op = op_in;
        test_count = test_count + 1;
        
        #1;
        
        if(op_in[4:2] == 3'b100) begin
            if(condition !== exp_cond) begin
                $error("[%0d] FAIL: %s", test_count, desc);
                $display("  got cond=%b, exp=%b", condition, exp_cond);
                error_count = error_count + 1;
            end
        end
        else begin
            if(result !== exp_result) begin
                $error("[%0d] FAIL: %s", test_count, desc);
                $display("  got res=%h, exp=%h", result, exp_result);
                error_count = error_count + 1;
            end
        end
    end
    endtask
    
    initial begin
        $dumpfile("alu_wave.vcd");
        $dumpvars(0, tb_ALU);
    end
    
endmodule