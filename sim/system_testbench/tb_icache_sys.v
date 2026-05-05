`timescale 1ns / 1ps
//
// tb_icache_sys.v — L1 指令 Cache 系统级集成验证
//
// 验证点：
//   T1: 冷启动 — CPU 通过 I$ 取指，首次 cold miss → refill → 返回指令
//   T2: 行内命中 — 同一 cache line 内连续取指无需再次 refill
//   T3: 跨行访问 — 顺序执行跨 cache line 边界，触发新的 refill
//   T4: 分支跳转 — 分支到已缓存行（命中）和未缓存行（miss → refill）
//   T5: 返回已缓存行 — 跳回之前访问过的行，验证命中
//

module tb_icache_sys;

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

    soc_top_bram_icache dut (
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
            // 用 NOP 填充 inst_mem
            for (i = 0; i < 1024; i = i + 1)
                dut.u_inst_mem.mem[i] = 32'h00000013;
            // 清零 data_mem
            for (i = 0; i < 1024; i = i + 1) begin
                dut.u_data_mem.mem0[i] = 8'h00;
                dut.u_data_mem.mem1[i] = 8'h00;
                dut.u_data_mem.mem2[i] = 8'h00;
                dut.u_data_mem.mem3[i] = 8'h00;
            end
            // 清零寄存器（x1-x31）
            for (i = 1; i < 32; i = i + 1)
                dut.u_core.u_regfile.regs[i] = 32'h00000000;
            repeat(2) @(posedge clk);
            rst_n = 1;
        end
    endtask

    `define REGS dut.u_core.u_regfile.regs

    // ============================================================
    initial begin
        $display("==================================================");
        $display("  L1 Inst Cache System-Level Testbench");
        $display("==================================================");

        // ========================================================
        // TEST 1: Cold start — 首次取指触发 cold miss → refill
        //
        // 程序（全部在 cache line 0, addr[5:4]=00）：
        //   0x00: addi x1, x0, 10       x1 = 10
        //   0x04: addi x2, x0, 20       x2 = 20
        //   0x08: addi x3, x0, 30       x3 = 30
        //   0x0C: addi x4, x0, 40       x4 = 40
        //
        // 预期：4 条指令在同一个 cache line 内，
        //   首次 0x00 cold miss → refill 整行 → 后续全部命中
        // ========================================================
        $display("\n--- TEST 1: Cold start, sequential fetch within one cache line ---");
        #1;
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00A00093; // addi x1, x0, 10
        dut.u_inst_mem.mem[1] = 32'h01400113; // addi x2, x0, 20
        dut.u_inst_mem.mem[2] = 32'h01E00193; // addi x3, x0, 30
        dut.u_inst_mem.mem[3] = 32'h02800213; // addi x4, x0, 40

        repeat(60) @(posedge clk);
        check_eq(`REGS[1], 32'd10, "T1 cold-start x1=10         ");
        check_eq(`REGS[2], 32'd20, "T1 line-hit   x2=20         ");
        check_eq(`REGS[3], 32'd30, "T1 line-hit   x3=30         ");
        check_eq(`REGS[4], 32'd40, "T1 line-hit   x4=40         ");

        // ========================================================
        // TEST 2: Cross-line access — 跨 cache line 边界
        //
        // 程序在 line 0 和 line 1 之间：
        //   0x00: addi x1, x0, 5        x1 = 5   [line 0]
        //   0x04: nop                            [line 0]
        //   0x08: nop                            [line 0]
        //   0x0C: jal  x0, +8          跳 0x14  [line 0]
        //   0x10: addi x3, x0, 99       [SQUASH] [line 1 word 0]
        //   0x14: addi x2, x0, 7        x2 = 7   [line 1 word 1]
        //   0x18: nop                            [line 1 word 2]
        //   0x1C: jal  x0, -8          跳 0x14  [line 1 word 3]
        //   0x14: (再次执行) x2 应为 7（覆盖写入）
        //
        // ========================================================
        $display("\n--- TEST 2: Cross cache line with JAL ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00500093; // addi x1, x0, 5
        dut.u_inst_mem.mem[1] = 32'h00000013; // nop
        dut.u_inst_mem.mem[2] = 32'h00000013; // nop
        dut.u_inst_mem.mem[3] = 32'h0080006F; // jal x0, +8
        dut.u_inst_mem.mem[4] = 32'h06300193; // addi x3, x0, 99  [SQUASH]
        dut.u_inst_mem.mem[5] = 32'h00700113; // addi x2, x0, 7   [TARGET]
        dut.u_inst_mem.mem[6] = 32'h00000013; // nop
        dut.u_inst_mem.mem[7] = 32'hFF9FF06F; // jal x0, -8 (jump back to 0x14)

        repeat(80) @(posedge clk);
        check_eq(`REGS[1], 32'd5,  "T2 line0       x1=5         ");
        check_eq(`REGS[2], 32'd7,  "T2 line1-jump  x2=7         ");
        check_eq(`REGS[3], 32'd0,  "T2 squash      x3=0         ");

        // ========================================================
        // TEST 3: 分支跳转到远地址（触发新的 cache line refill）
        //
        //   0x00: addi x1, x0, 5        [line 0]
        //   0x04: addi x2, x0, 5        [line 0]
        //   0x08: beq  x1, x2, +32      跳 0x28 [line 0]
        //   0x0C-0x24: 全是 NOP + addi x3 （应被跳过）
        //   0x28: addi x4, x0, 42       [TARGET — line 2 word 2]
        //
        // 这验证了：
        //   - 分支目标在不同 cache line 时触发 refill
        //   - 被跳过的指令不会执行
        // ========================================================
        $display("\n--- TEST 3: Branch to distant address (new cache line) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00500093; // addi x1, x0, 5
        dut.u_inst_mem.mem[1] = 32'h00500113; // addi x2, x0, 5
        // beq x1, x2, +32: offset=32 → target = 0x08 + 32 = 0x28
        dut.u_inst_mem.mem[2] = 32'h02208063;
        // 0x0C - 0x24: 被跳过的指令
        dut.u_inst_mem.mem[3] = 32'h06300193; // addi x3, x0, 99  [SQUASH]
        dut.u_inst_mem.mem[4] = 32'h00000013; // nop
        dut.u_inst_mem.mem[5] = 32'h00000013; // nop
        dut.u_inst_mem.mem[6] = 32'h00000013; // nop
        dut.u_inst_mem.mem[7] = 32'h00000013; // nop
        dut.u_inst_mem.mem[8] = 32'h00000013; // nop
        dut.u_inst_mem.mem[9] = 32'h00000013; // nop
        // 0x28: target
        dut.u_inst_mem.mem[10] = 32'h02A00213; // addi x4, x0, 42

        repeat(80) @(posedge clk);
        check_eq(`REGS[3], 32'd0,  "T3 squash      x3=0         ");
        check_eq(`REGS[4], 32'd42, "T3 far-branch  x4=42        ");

        // ========================================================
        // TEST 4: 同 index 不同 tag —— 两路缓存独立工作
        //
        // BLOCK_WIDTH=4, GROUP_NUM_WIDTH=4 → index = addr[7:4]
        //   0x000: index=0, tag=0x000000 → way 0
        //   0x100: index=0, tag=0x000001 → way 1
        //
        // 流程：
        //   0x000: addi x1, x0, 1   (x1=1, way 0 miss→refill)
        //   0x004: jal → 0x104
        //   0x100: addi x2, x0, 2   (x2=2, way 1 miss→refill, 不驱逐 way 0)
        //   0x104: add  x3, x1, x2  (x3=1+2=3)
        //   0x108: nop; 0x10C: nop
        // ========================================================
        $display("\n--- TEST 4: Same-index different-tag (two-way) hit ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00100093; // addi x1, x0, 1
        dut.u_inst_mem.mem[1] = 32'h0FC0006F; // jal x0, +252 → 0x100
        dut.u_inst_mem.mem[2] = 32'h00000013; // nop
        dut.u_inst_mem.mem[3] = 32'h00000013; // nop
        // 0x010-0x0FC: all NOP (from do_reset)
        dut.u_inst_mem.mem[64] = 32'h00200113; // addi x2, x0, 2   [0x100]
        dut.u_inst_mem.mem[65] = 32'h002081B3; // add x3, x1, x2   [0x104]
        dut.u_inst_mem.mem[66] = 32'h00000013; // nop              [0x108]
        dut.u_inst_mem.mem[67] = 32'h00000013; // nop              [0x10C]

        repeat(120) @(posedge clk);
        check_eq(`REGS[1], 32'd1,  "T4 way0        x1=1         ");
        check_eq(`REGS[2], 32'd2,  "T4 way1        x2=2         ");
        check_eq(`REGS[3], 32'd3,  "T4 sum         x3=3         ");

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
