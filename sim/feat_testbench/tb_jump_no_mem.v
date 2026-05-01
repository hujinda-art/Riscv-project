`timescale 1ns / 1ps

// tb_jump_no_mem.v
// 在无 Load/Store 指令的纯净场景下，验证 CPU 数据通路及跳转处理：
//   - JAL  提前解析（IF/ID 阶段 redirect + write-port-2 link）
//   - JALR EX 阶段解析（rd = PC+4，非目标地址）
//   - BEQ  taken      （EX 分支 flush）
//   - BNE  not taken  （顺序执行）
//   - BLT  taken      （有符号比较 + backward branch）
//   - Backward loop   （验证重复跳转与前递通路）
// 若所有断言通过，则显示 PASS 并结束仿真。

module tb_jump_no_mem;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg        stall = 1'b0;
    reg        flush = 1'b0;
    reg        exception = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg        interrupt = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] instr_out;
    wire        instr_valid_out;
    wire [6:0]  fun7_out;
    wire [4:0]  rs2_out;
    wire [4:0]  rs1_out;
    wire [2:0]  fuc3_out;
    wire [6:0]  opcode_out;
    wire [4:0]  rd_out;
    wire [31:0] ex_pc_out;
    wire [31:0] ex_pc_plus4_out;
    wire [31:0] ex_instr_out;
    wire        ex_instr_valid_out;
    wire [31:0] ex_imm_out;
    wire [31:0] ex_result_out;
    wire [31:0] ex_mem_addr_out;
    wire [31:0] ex_mem_wdata_out;

    soc_top_bram dut (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .exception(exception),
        .pc_exception(pc_exception),
        .interrupt(interrupt),
        .pc_interrupt(pc_interrupt),
        .id_pc(id_pc),
        .id_pc_plus4(id_pc_plus4),
        .instr_out(instr_out),
        .instr_valid_out(instr_valid_out),
        .fun7_out(fun7_out),
        .rs2_out(rs2_out),
        .rs1_out(rs1_out),
        .fuc3_out(fuc3_out),
        .opcode_out(opcode_out),
        .rd_out(rd_out),
        .ex_pc_out(ex_pc_out),
        .ex_pc_plus4_out(ex_pc_plus4_out),
        .ex_instr_out(ex_instr_out),
        .ex_instr_valid_out(ex_instr_valid_out),
        .ex_imm_out(ex_imm_out),
        .ex_result_out(ex_result_out),
        .ex_mem_addr_out(ex_mem_addr_out),
        .ex_mem_wdata_out(ex_mem_wdata_out)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    task check_reg(input [4:0] regno, input [31:0] expected, input [255:0] msg);
        begin
            if (dut.u_core.u_regfile.regs[regno] !== expected) begin
                $display("FAIL: %s  reg[%0d]=%0d (expected %0d)", msg, regno,
                         dut.u_core.u_regfile.regs[regno], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %s", msg);
            end
        end
    endtask

    initial begin
        // 延后一拍写 mem，避免覆盖 inst_mem initial（全表清 NOP）在 time 0 的值
        #1;

        // ================================================================
        // TEST 1: JAL early resolve in IF/ID
        //   0x00: addi x1, x0, 5       -> x1 = 5
        //   0x04: jal  x2, +8          -> x2 = 0x08, PC = 0x0C
        //   0x08: addi x3, x0, 99      -> [SQUASHED]
        //   0x0C: addi x4, x0, 7       -> x4 = 7
        // ================================================================
        dut.u_inst_mem.mem[0]  = 32'h00500093; // addi x1, x0, 5
        dut.u_inst_mem.mem[1]  = 32'h0080016F; // jal  x2, +8
        dut.u_inst_mem.mem[2]  = 32'h06300193; // addi x3, x0, 99
        dut.u_inst_mem.mem[3]  = 32'h00700213; // addi x4, x0, 7

        // ================================================================
        // TEST 2: JALR (EX stage, rd = PC+4)
        //   0x10: addi x5, x0, 0x24    -> x5 = 0x24
        //   0x14: jalr x6, x5, 0       -> x6 = 0x18, PC = 0x24
        //   0x18: addi x7, x0, 99      -> [SQUASHED]
        //   0x1C: nop
        //   0x20: nop
        //   0x24: addi x8, x0, 9       -> x8 = 9
        // ================================================================
        dut.u_inst_mem.mem[4]  = 32'h02400293; // addi x5, x0, 0x24
        dut.u_inst_mem.mem[5]  = 32'h00028367; // jalr x6, x5, 0
        dut.u_inst_mem.mem[6]  = 32'h06300393; // addi x7, x0, 99
        dut.u_inst_mem.mem[7]  = 32'h00000013; // nop
        dut.u_inst_mem.mem[8]  = 32'h00000013; // nop
        dut.u_inst_mem.mem[9]  = 32'h00900413; // addi x8, x0, 9

        // ================================================================
        // TEST 3: BEQ taken (flush IF/ID + ID/EX)
        //   0x28: addi x9,  x0, 10     -> x9  = 10
        //   0x2C: addi x10, x0, 10     -> x10 = 10
        //   0x30: beq  x9, x10, +12    -> taken, PC = 0x3C
        //   0x34: addi x11, x0, 99     -> [SQUASHED]
        //   0x38: addi x11, x0, 98     -> [SQUASHED]
        //   0x3C: addi x12, x0, 11     -> x12 = 11
        // ================================================================
        dut.u_inst_mem.mem[10] = 32'h00A00493; // addi x9,  x0, 10
        dut.u_inst_mem.mem[11] = 32'h00A00513; // addi x10, x0, 10
        dut.u_inst_mem.mem[12] = 32'h00528663; // beq  x9, x10, +12
        dut.u_inst_mem.mem[13] = 32'h06300593; // addi x11, x0, 99
        dut.u_inst_mem.mem[14] = 32'h06200593; // addi x11, x0, 98
        dut.u_inst_mem.mem[15] = 32'h00B00613; // addi x12, x0, 11

        // ================================================================
        // TEST 4: BNE not taken (sequential execution)
        //   0x40: bne  x9, x10, +8     -> not taken (x9 == x10)
        //   0x44: addi x13, x0, 13     -> x13 = 13
        //   0x48: nop
        //   0x4C: addi x14, x0, 14     -> x14 = 14
        // ================================================================
        dut.u_inst_mem.mem[16] = 32'h00A49463; // bne  x9, x10, +8
        dut.u_inst_mem.mem[17] = 32'h00D00693; // addi x13, x0, 13
        dut.u_inst_mem.mem[18] = 32'h00000013; // nop
        dut.u_inst_mem.mem[19] = 32'h00E00713; // addi x14, x0, 14

        // ================================================================
        // TEST 5: BLT taken (signed comparison)
        //   0x50: addi x15, x0, 5      -> x15 = 5
        //   0x54: blt  x15, x9, +8     -> taken (5 < 10), PC = 0x5C
        //   0x58: addi x16, x0, 99     -> [SQUASHED]
        //   0x5C: addi x17, x0, 17     -> x17 = 17
        // ================================================================
        dut.u_inst_mem.mem[20] = 32'h00500793; // addi x15, x0, 5
        dut.u_inst_mem.mem[21] = 32'h0097C463; // blt  x15, x9, +8
        dut.u_inst_mem.mem[22] = 32'h06300813; // addi x16, x0, 99
        dut.u_inst_mem.mem[23] = 32'h01100893; // addi x17, x0, 17

        // ================================================================
        // TEST 6: Backward branch loop (3 iterations)
        //   0x60: addi x18, x0, 0      -> x18 = 0
        //   0x64: addi x18, x18, 1     -> x18++
        //   0x68: addi x19, x0, 3      -> x19 = 3
        //   0x6C: blt  x18, x19, -12   -> loop back to 0x64 while x18 < 3
        //   0x70: addi x20, x0, 20     -> x20 = 20
        // ================================================================
        dut.u_inst_mem.mem[24] = 32'h00000913; // addi x18, x0, 0
        dut.u_inst_mem.mem[25] = 32'h00190913; // addi x18, x18, 1
        dut.u_inst_mem.mem[26] = 32'h00300993; // addi x19, x0, 3
        dut.u_inst_mem.mem[27] = 32'hFF394CE3; // blt  x18, x19, -8
        dut.u_inst_mem.mem[28] = 32'h01400A13; // addi x20, x0, 20

        // 其余填 NOP，防止取到未知指令
        dut.u_inst_mem.mem[29] = 32'h0000006F; // jal x0, 0 (self-loop)
        dut.u_inst_mem.mem[30] = 32'h00000013;
        dut.u_inst_mem.mem[31] = 32'h00000013;

        #20 rst_n = 1'b1;

        // 约 150 周期足够跑完所有测试（含循环气泡）
        repeat (150) @(posedge clk);

        $display("\n========== Jump-Only Test Results ==========");

        // TEST 1
        check_reg(1,  32'd5,   "T1  addi x1");
        check_reg(2,  32'h08,  "T1  jal  x2 (link = PC+4)");
        check_reg(3,  32'd0,   "T1  squash x3");
        check_reg(4,  32'd7,   "T1  target x4");

        // TEST 2
        check_reg(5,  32'h24,  "T2  addi x5 (JALR base)");
        check_reg(6,  32'h18,  "T2  jalr x6 (link = PC+4)");
        check_reg(7,  32'd0,   "T2  squash x7");
        check_reg(8,  32'd9,   "T2  target x8");

        // TEST 3
        check_reg(9,  32'd10,  "T3  addi x9");
        check_reg(10, 32'd10,  "T3  addi x10");
        check_reg(11, 32'd0,   "T3  squash x11 (BEQ taken)");
        check_reg(12, 32'd11,  "T3  target x12");

        // TEST 4
        check_reg(13, 32'd13,  "T4  addi x13 (BNE not taken)");
        check_reg(14, 32'd14,  "T4  addi x14");

        // TEST 5
        check_reg(15, 32'd5,   "T5  addi x15");
        check_reg(16, 32'd0,   "T5  squash x16 (BLT taken)");
        check_reg(17, 32'd17,  "T5  target x17");

        // TEST 6
        check_reg(18, 32'd3,   "T6  loop x18 (3 iterations)");
        check_reg(19, 32'd3,   "T6  addi x19 (loop limit)");
        check_reg(20, 32'd20,  "T6  addi x20 (after loop)");

        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d TEST(S) FAILED ***", errors);

        $display("============================================\n");
        $stop;
    end
endmodule
