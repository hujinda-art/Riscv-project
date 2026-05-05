`timescale 1ns / 1ps
//
// tb_m_extension.v — RV32M (M extension) 验证
//
// 验证点：
//   T1: MUL  — 有符号乘法低32位
//   T2: MULH — 有符号乘法高32位
//   T3: MULHU — 无符号乘法高32位
//   T4: MULHSU — 有符号×无符号乘法高32位
//   T5: DIV  — 有符号除法（含溢出）
//   T6: DIVU — 无符号除法
//   T7: REM  — 有符号取余（含溢出）
//   T8: REMU — 无符号取余
//   T9: 除零 — DIV/DIVU/REM/REMU by zero
//

module tb_m_extension;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    reg stall = 1'b0;
    reg flush = 1'b0;
    reg        exception    = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg        interrupt    = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

    wire [31:0] id_pc, id_pc_plus4, instr_out;
    wire        instr_valid_out;
    wire [6:0]  fun7_out;
    wire [4:0]  rs2_out, rs1_out, rd_out;
    wire [2:0]  fuc3_out;
    wire [6:0]  opcode_out;
    wire [31:0] ex_pc_out, ex_pc_plus4_out, ex_instr_out, ex_imm_out;
    wire        ex_instr_valid_out;
    wire [31:0] ex_result_out, ex_mem_addr_out, ex_mem_wdata_out;

    soc_top_bram_dcache dut (
        .clk(clk), .rst_n(rst_n),
        .stall(stall), .flush(flush),
        .exception(exception), .pc_exception(pc_exception),
        .interrupt(interrupt), .pc_interrupt(pc_interrupt),
        .id_pc(id_pc), .id_pc_plus4(id_pc_plus4),
        .instr_out(instr_out), .instr_valid_out(instr_valid_out),
        .fun7_out(fun7_out), .rs2_out(rs2_out), .rs1_out(rs1_out),
        .fuc3_out(fuc3_out), .opcode_out(opcode_out), .rd_out(rd_out),
        .ex_pc_out(ex_pc_out), .ex_pc_plus4_out(ex_pc_plus4_out),
        .ex_instr_out(ex_instr_out), .ex_instr_valid_out(ex_instr_valid_out),
        .ex_imm_out(ex_imm_out),
        .ex_result_out(ex_result_out),
        .ex_mem_addr_out(ex_mem_addr_out),
        .ex_mem_wdata_out(ex_mem_wdata_out)
    );

    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task check_eq;
        input [31:0]      actual;
        input [31:0]      expected;
        input [8*40-1:0]  label;
        begin
            if (actual !== expected) begin
                $display("  FAIL [%0s]  got=0x%08X  expected=0x%08X",
                         label, actual, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS [%0s]  = 0x%08X", label, expected);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task do_reset;
        integer i;
        begin
            rst_n = 0;
            for (i = 0; i < 1024; i = i + 1)
                dut.u_inst_mem.mem[i] = 32'h00000013;
            for (i = 0; i < 1024; i = i + 1) begin
                dut.u_data_mem.mem0[i] = 8'h00;
                dut.u_data_mem.mem1[i] = 8'h00;
                dut.u_data_mem.mem2[i] = 8'h00;
                dut.u_data_mem.mem3[i] = 8'h00;
            end
            for (i = 1; i < 32; i = i + 1)
                dut.u_core.u_regfile.regs[i] = 32'h00000000;
            repeat(2) @(posedge clk);
            rst_n = 1;
        end
    endtask

    `define REGS dut.u_core.u_regfile.regs

    initial begin
        $display("==================================================");
        $display("  RV32M Extension Testbench");
        $display("==================================================");

        // ========================================================
        // 初始化寄存器：
        //   x1  = 6
        //   x2  = 7
        //   x3  = 0x800 (-2048 signed, 2048 unsigned)
        //   x4  = 0x80000000 (-2^31 signed, 2^31 unsigned)
        //   x5  = -1 (0xFFFFFFFF signed, 2^32-1 unsigned)
        //   x6  = 0
        //   x7  = 3
        //
        // 指令内存布局（0x00 起始）：
        // ========================================================
        $display("\n--- Initializing registers ---");
        do_reset;

        // === 初始化 ===
        dut.u_inst_mem.mem[0]  = 32'h00600093;  // 0x00: addi x1, x0, 6
        dut.u_inst_mem.mem[1]  = 32'h00700113;  // 0x04: addi x2, x0, 7
        dut.u_inst_mem.mem[2]  = 32'h80000193;  // 0x08: addi x3, x0, 0x800
        dut.u_inst_mem.mem[3]  = 32'h80000237;  // 0x0C: lui  x4, 0x80000
        dut.u_inst_mem.mem[4]  = 32'hFFF00293;  // 0x10: addi x5, x0, -1
        dut.u_inst_mem.mem[5]  = 32'h00000313;  // 0x14: addi x6, x0, 0
        dut.u_inst_mem.mem[6]  = 32'h00300393;  // 0x18: addi x7, x0, 3
        // NOP 隔离，确保寄存器写入完成
        dut.u_inst_mem.mem[7]  = 32'h00000013;  // 0x1C: nop
        dut.u_inst_mem.mem[8]  = 32'h00000013;  // 0x20: nop
        dut.u_inst_mem.mem[9]  = 32'h00000013;  // 0x24: nop

        // === MUL/MULH/MULHU/MULHSU 测试 ===
        dut.u_inst_mem.mem[10] = 32'h02208433;  // 0x28: MUL    x8,  x1, x2  → x8  = 6*7 = 42
        dut.u_inst_mem.mem[11] = 32'h022094B3;  // 0x2C: MULH   x9,  x1, x2  → x9  = high32(6*7) = 0
        dut.u_inst_mem.mem[12] = 32'h02521533;  // 0x30: MULH   x10, x4, x5  → x10 = high32(0x80000000 * -1) = 0
        dut.u_inst_mem.mem[13] = 32'h025235B3;  // 0x34: MULHU  x11, x4, x5  → x11 = 0x7FFFFFFF
        dut.u_inst_mem.mem[14] = 32'h02122633;  // 0x38: MULHSU x12, x4, x1  → x12 = 0xFFFFFFFD
        // NOP 隔离
        dut.u_inst_mem.mem[15] = 32'h00000013;  // 0x3C: nop

        // === DIV/DIVU 测试 ===
        dut.u_inst_mem.mem[16] = 32'h027146B3;  // 0x40: DIV    x13, x2, x7  → 7/3 = 2
        dut.u_inst_mem.mem[17] = 32'h02524733;  // 0x44: DIV    x14, x4, x5  → overflow = 0x80000000
        dut.u_inst_mem.mem[18] = 32'h027257B3;  // 0x48: DIVU   x15, x4, x7  → 0x80000000/3 = 0x2AAAAAAA
        // NOP 隔离
        dut.u_inst_mem.mem[19] = 32'h00000013;  // 0x4C: nop

        // === REM/REMU 测试 ===
        dut.u_inst_mem.mem[20] = 32'h02716833;  // 0x50: REM    x16, x2, x7  → 7%3 = 1
        dut.u_inst_mem.mem[21] = 32'h025268B3;  // 0x54: REM    x17, x4, x5  → overflow rem = 0
        dut.u_inst_mem.mem[22] = 32'h02727933;  // 0x58: REMU   x18, x4, x7  → 0x80000000%3 = 2
        // NOP 隔离
        dut.u_inst_mem.mem[23] = 32'h00000013;  // 0x5C: nop

        // === 除零测试 ===
        dut.u_inst_mem.mem[24] = 32'h0260C9B3;  // 0x60: DIV    x19, x1, x6  → 6/0 = 0xFFFFFFFF
        dut.u_inst_mem.mem[25] = 32'h0260DA33;  // 0x64: DIVU   x20, x1, x6  → 6/0 = 0xFFFFFFFF
        dut.u_inst_mem.mem[26] = 32'h0260EAB3;  // 0x68: REM    x21, x1, x6  → 6%0 = 6
        dut.u_inst_mem.mem[27] = 32'h0260FB33;  // 0x6C: REMU   x22, x1, x6  → 6%0 = 6

        // 余下用 NOP 填充
        repeat(120) @(posedge clk);

        // ========================================================
        // 结果检查
        // ========================================================
        $display("\n--- Initial register checks ---");
        check_eq(`REGS[1], 32'h00000006, "Init  x1  = 6              ");
        check_eq(`REGS[2], 32'h00000007, "Init  x2  = 7              ");
        check_eq(`REGS[4], 32'h80000000, "Init  x4  = 0x80000000     ");
        check_eq(`REGS[5], 32'hFFFFFFFF, "Init  x5  = -1             ");
        check_eq(`REGS[6], 32'h00000000, "Init  x6  = 0              ");
        check_eq(`REGS[7], 32'h00000003, "Init  x7  = 3              ");

        $display("\n--- MUL / MULH / MULHU / MULHSU ---");
        check_eq(`REGS[8],  32'h0000002A, "MUL      6*7      = 42      ");
        check_eq(`REGS[9],  32'h00000000, "MULH     hi(6*7)  = 0       ");
        check_eq(`REGS[10], 32'h00000000, "MULH     hi(0x80000000*-1)=0");
        check_eq(`REGS[11], 32'h7FFFFFFF, "MULHU    hi(0x80000000*0xFFFFFFFF)");
        check_eq(`REGS[12], 32'hFFFFFFFD, "MULHSU   hi(0x80000000*6)  ");

        $display("\n--- DIV / DIVU ---");
        check_eq(`REGS[13], 32'h00000002, "DIV      7/3      = 2       ");
        check_eq(`REGS[14], 32'h80000000, "DIV      overflow = 0x80000000");
        check_eq(`REGS[15], 32'h2AAAAAAA, "DIVU     0x80000000/3      ");

        $display("\n--- REM / REMU ---");
        check_eq(`REGS[16], 32'h00000001, "REM      7%3      = 1       ");
        check_eq(`REGS[17], 32'h00000000, "REM      overflow = 0       ");
        check_eq(`REGS[18], 32'h00000002, "REMU     0x80000000%3 = 2   ");

        $display("\n--- Divide by Zero ---");
        check_eq(`REGS[19], 32'hFFFFFFFF, "DIV/0    6/0      = 0xFFFFFFFF");
        check_eq(`REGS[20], 32'hFFFFFFFF, "DIVU/0   6/0      = 0xFFFFFFFF");
        check_eq(`REGS[21], 32'h00000006, "REM/0    6%0      = 6       ");
        check_eq(`REGS[22], 32'h00000006, "REMU/0   6%0      = 6       ");

        // ========================================================
        // Summary
        // ========================================================
        $display("");
        $display("==================================================");
        $display("  RESULT: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d TEST(s) FAILED -- see FAIL lines above <<<",
                     fail_count);
        $display("==================================================");

        $finish;
    end

endmodule
