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
    wire        cout;
    wire        condition;
    
    integer error_count = 0;
    integer test_count = 0;
    integer j = 0;
    ALU u_alu(
        .a(a),
        .b(b),
        .op(op),
        .result(result),
        .cout(cout),
        .condition(condition)
    );
    
    initial clk = 0; 
    always begin
        #10
        clk = ~clk;
    end
    
    always @(posedge clk) begin :count_block // 算术运算测试
        if(j < 4) begin
        case(j)
      
        1'd0:test_one(5'b00000, 32'd5, 32'd3, 32'd8, 1'b0, 1'bx, "5+3=8");
        1'd1:test_one(5'b00000, 32'hFFFFFFFF, 32'd1, 32'd0, 1'b1, 1'bx, "FFFFFFFF+1=0");
        
        2'd2:test_one(5'b00001, 32'd5, 32'd3, 32'd2, 1'b0, 1'bx, "5-3=2");
        2'd3:test_one(5'b00010, 32'd5, 32'd3, 32'd15, 1'b0, 1'bx, "5*3=15");
        
        endcase
        j = j + 1;
        end else begin
            disable count_block;
        end
     end
     
    initial begin
        #100;
      
    
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
        input        cout_in;
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
        else if (op_in[4] == 1'b0) begin
            if (result !== exp_result) begin
                $error("[%0d] FAIL: %s", test_count, desc);
                $display("  got res=%h, exp=%h", result, exp_result);
                error_count = error_count + 1;
            end
        end
        $display("%s,%d", desc, cout);
        
    end
    endtask
    
    initial begin
        $dumpfile("alu_wave.vcd");
        $dumpvars(0, tb_ALU);
    end
    
endmodule