`timescale 1ns / 1ps
//
// tb_dcache_sys.v — L1 数据 Cache 系统级集成验证
//
// 验证点：
//   T1: SW→LW 同地址 — 写直达后读回，验证基本通路
//   T2: LW miss → refill → LW hit — 读未命中回填后命中
//   T3: 不同 cache line 独立访问 — 验证不同 index 间隔离
//   T4: 子字访问 SB/LB — 验证字节粒度读写与符号扩展
//

module tb_dcache_sys;

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
        $display("  L1 Data Cache System-Level Testbench");
        $display("==================================================");

        // ========================================================
        // TEST 1: SW→LW 同地址 — 写直达 + 读回
        //
        //   0x00: addi x1, x0, 0x55       x1 = 0x55
        //   0x04: addi x2, x0, 0x10       x2 = 0x10
        //   0x08: sw   x1, 0(x2)          [0x10] = 0x55 (写直达)
        //   0x0C: lw   x3, 0(x2)          x3 = [0x10]
        //
        // 预期：x3 = 0x55
        // ========================================================
        $display("\n--- TEST 1: SW then LW same address (write-through) ---");
        #1;
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h05500093; // addi x1, x0, 0x55
        dut.u_inst_mem.mem[1] = 32'h01000113; // addi x2, x0, 0x10
        dut.u_inst_mem.mem[2] = 32'h00112023; // sw   x1, 0(x2)
        dut.u_inst_mem.mem[3] = 32'h00012183; // lw   x3, 0(x2)

        repeat(60) @(posedge clk);
        check_eq(`REGS[1], 32'h55, "T1 data         x1=0x55      ");
        check_eq(`REGS[3], 32'h55, "T1 LW result    x3=0x55      ");

        // ========================================================
        // TEST 2: LW miss → refill → LW hit
        //
        // 预填充 data_mem[0x20] = 0xAA_BB_CC_DD，然后：
        //   0x00: addi x2, x0, 0x20       x2 = 0x20
        //   0x04: lw   x1, 0(x2)          x1 = [0x20] (miss → refill)
        //   0x08: lw   x3, 0(x2)          x3 = [0x20] (cache hit)
        //
        // 预期：x1 = x3 = 0xAABBCCDD
        // ========================================================
        $display("\n--- TEST 2: LW miss refill + LW hit ---");
        do_reset;
        // 预填充 data_mem 地址 0x20（word index = 0x20>>2 = 8）
        dut.u_data_mem.mem0[8] = 8'hDD;
        dut.u_data_mem.mem1[8] = 8'hCC;
        dut.u_data_mem.mem2[8] = 8'hBB;
        dut.u_data_mem.mem3[8] = 8'hAA;
        dut.u_inst_mem.mem[0] = 32'h02000113; // addi x2, x0, 0x20
        dut.u_inst_mem.mem[1] = 32'h00012083; // lw   x1, 0(x2)
        dut.u_inst_mem.mem[2] = 32'h00012183; // lw   x3, 0(x2)

        repeat(80) @(posedge clk);
        check_eq(`REGS[1], 32'hAABBCCDD, "T2 LW miss     x1=AABBCCDD  ");
        check_eq(`REGS[3], 32'hAABBCCDD, "T2 LW hit      x3=AABBCCDD  ");

        // ========================================================
        // TEST 3: 不同 cache line 独立访问
        //
        // BLOCK_WIDTH=4, GROUP_NUM_WIDTH=4 → index = addr[7:4]
        //   0x30: index=3, 0x50: index=5 （不同 cache line）
        //
        // 使用完全独立的寄存器，避免任何转发/寄存器复用问题
        //   0x00: addi x1, x0, 0x11       x1 = 0x11 (data1)
        //   0x04: addi x7, x0, 0x30       x7 = 0x30 (addr1)
        //   0x08: sw   x1, 0(x7)          [0x30] = 0x11
        //   0x0C: addi x3, x0, 0x42       x3 = 0x42 (data2)
        //   0x10: addi x8, x0, 0x50       x8 = 0x50 (addr2)
        //   0x14: sw   x3, 0(x8)          [0x50] = 0x42
        //   0x18: nop
        //   0x1C: nop
        //   0x20: lw   x5, 0(x8)          x5 = [0x50] = 0x42
        //   0x24: nop
        //   0x28: lw   x6, 0(x7)          x6 = [0x30] = 0x11
        //
        // 预期：x5 = 0x42, x6 = 0x11
        // ========================================================
        $display("\n--- TEST 3: Different cache lines (independent regs) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h01100093; // addi x1, x0, 0x11
        dut.u_inst_mem.mem[1] = 32'h03000393; // addi x7, x0, 0x30
        dut.u_inst_mem.mem[2] = 32'h0013a023; // sw   x1, 0(x7)
        dut.u_inst_mem.mem[3] = 32'h04200193; // addi x3, x0, 0x42
        dut.u_inst_mem.mem[4] = 32'h05000413; // addi x8, x0, 0x50
        dut.u_inst_mem.mem[5] = 32'h00342023; // sw   x3, 0(x8)
        dut.u_inst_mem.mem[6] = 32'h00000013; // nop
        dut.u_inst_mem.mem[7] = 32'h00000013; // nop
        dut.u_inst_mem.mem[8] = 32'h00042283; // lw   x5, 0(x8)
        dut.u_inst_mem.mem[9] = 32'h00000013; // nop
        dut.u_inst_mem.mem[10]= 32'h0003a303; // lw   x6, 0(x7)

        repeat(100) @(posedge clk);

        check_eq(`REGS[5], 32'h42, "T3 line5       x5=0x42      ");
        check_eq(`REGS[6], 32'h11, "T3 line3       x6=0x11      ");
        // ========================================================
        // TEST 4: 子字访问 SB/LB（验证符号扩展 + 字节粒度）
        //
        //   0x00: addi x1, x0, 0x7B       x1 = 0x7B
        //   0x04: addi x2, x0, 0x40       x2 = 0x40
        //   0x08: sb   x1, 0(x2)          [0x40] = 0x7B (byte)
        //   0x0C: lb   x3, 0(x2)          x3 = sign-ext([0x40])
        //
        // 0x7B = 0111_1011，符号位 bit7=0 → 零扩展 → 0x0000007B
        //
        // ========================================================
        $display("\n--- TEST 4: Sub-word SB/LB ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h07B00093; // addi x1, x0, 0x7B
        dut.u_inst_mem.mem[1] = 32'h04000113; // addi x2, x0, 0x40
        dut.u_inst_mem.mem[2] = 32'h00110023; // sb   x1, 0(x2)
        dut.u_inst_mem.mem[3] = 32'h00010183; // lb   x3, 0(x2)

        repeat(60) @(posedge clk);
        check_eq(`REGS[3], 32'h7B, "T4 SB/LB       x3=0x7B      ");

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
