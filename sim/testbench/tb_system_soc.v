`timescale 1ns / 1ps

// ============================================================================
// tb_system_soc — SoC 级系统仿真（与 scripts/sw/full_instr_test.c 配套）
//
// 约定（与 C 侧一致）：
//   - 完成标志：DMEM 字节地址 0x80 写 32'hC001D00D（DONE_MAGIC）
//   - 签名区：  0x100 起，每槽 4 字节，共 18 个 uint32_t 结果供 TB 比对
//   - 程序结束：自陷死循环（j .），DONE 必须先于自陷写入
//
// TB 流程概要：
//   1) 清零 DMEM；可选 $readmemh 覆盖 IMEM（+IMEM_HEX），否则用 inst_mem_program.vh
//   2) 校验 IMEM[0] 指纹（startup 首条 auipc）
//   3) 释放复位后可选打印 TRACE，再轮询 DONE 直到超时或成功
//   4) 成功则逐项 check_sig；失败则 dump DMEM 辅助定位
//
// 注意：data_mem 为四字节 lane（mem0..mem3），读字需按小端拼成 32 位。
// ============================================================================
module tb_system_soc;
    // 时钟 100MHz（周期 10ns）
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    // 核侧控制：本 TB 默认不拉 stall/flush/异常/中断，仅接 DUT 端口
    reg stall = 1'b0;
    reg flush = 1'b0;
    reg exception = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg interrupt = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

    // 来自 core_top 的探测信号（便于 TRACE / 超时打印）
    wire [31:0] id_pc, id_pc_plus4, instr_out;
    wire instr_valid_out;
    wire [6:0] fun7_out;
    wire [4:0] rs2_out, rs1_out, rd_out;
    wire [2:0] fuc3_out;
    wire [6:0] opcode_out;
    wire [31:0] ex_pc_out, ex_pc_plus4_out, ex_instr_out, ex_imm_out;
    wire ex_instr_valid_out;
    wire [31:0] ex_result_out, ex_mem_addr_out, ex_mem_wdata_out;

    // DUT：核 + inst_mem + data_mem（层次名 dut.u_core / dut.u_inst_mem / dut.u_data_mem）
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

    // 统计：仅在「成功进入签名检查」阶段递增；超时仅 fail_count+1
    integer pass_count = 0;
    integer fail_count = 0;
    integer i;
    integer dbg_cycle;
    reg     mem_done_ok;

    // --- 与 C 程序 full_instr_test.c 中宏一致 ---
    localparam [31:0] DONE_MAGIC = 32'hC001D00D;
    // DMEM 按字索引：字节地址 >> 2
    localparam integer DONE_WORD = 32'h00000080 >> 2;
    localparam integer SIG_BASE_WORD = 32'h00000100 >> 2;
    localparam integer MAX_CYCLES = 50000;
    localparam integer NUM_SIG_CHECKS = 18;
    // startup.S 首条指令 auipc sp,0x1 的机器码，用于确认 IMEM 已烧录
    localparam [31:0] EXPECTED_IMEM_W0 = 32'h00001117;
    reg [1023:0] imem_hex_path;
    integer imem_hex_plusarg_ok;

    // data_mem 为 4 个 8bit BRAM：同一 word 索引 wi 下拼成小端 32 位字
    function [31:0] dmem_read_word;
        input integer wi;
        begin
            dmem_read_word = {
                dut.u_data_mem.mem3[wi],
                dut.u_data_mem.mem2[wi],
                dut.u_data_mem.mem1[wi],
                dut.u_data_mem.mem0[wi]
            };
        end
    endfunction

    // 仿真初始化时把 DMEM 某字写成 w（TB 用其清零）
    task dmem_write_word;
        input integer wi;
        input [31:0] w;
        begin
            dut.u_data_mem.mem0[wi] = w[7:0];
            dut.u_data_mem.mem1[wi] = w[15:8];
            dut.u_data_mem.mem2[wi] = w[23:16];
            dut.u_data_mem.mem3[wi] = w[31:24];
        end
    endtask

    // 比对签名槽 sig[idx]（内存字地址 = SIG_BASE_WORD + idx）
    task check_sig;
        input integer idx;
        input [31:0] expected;
        input [255:0] name;
        reg [31:0] got;
        begin
            got = dmem_read_word(SIG_BASE_WORD + idx);
            if (got === expected) begin
                $display("  PASS [%-24s] = 0x%08h", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%-24s] got=0x%08h expected=0x%08h", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("  System-level CPU TB (self-trap end condition)");
        $display("==================================================");

        rst_n = 1'b0;

        // DMEM 深度与 SOC_DMEM_ADDR_WIDTH 一致（此处 1024 字）
        for (i = 0; i < 1024; i = i + 1)
            dmem_write_word(i, 32'h00000000);

        // 可选：Vivado 仿真 cwd 不在仓库根时，用 -testplusarg IMEM_HEX=<绝对路径.hex>
        imem_hex_plusarg_ok = $value$plusargs("IMEM_HEX=%s", imem_hex_path);
        if (imem_hex_plusarg_ok != 0) begin
            $display("TB: overriding IMEM from plusarg IMEM_HEX: %s", imem_hex_path);
            $readmemh(imem_hex_path, dut.u_inst_mem.mem);
        end else begin
            $display("TB: using baked-in program from inst_mem_program.vh (no IMEM_HEX given)");
        end

        // 等一个 delta，让 inst_mem initial 与 $readmemh 在 time-0 落定
        #1;
        $display("TB: IMEM[0..3] = %08h %08h %08h %08h",
                 dut.u_inst_mem.mem[0], dut.u_inst_mem.mem[1],
                 dut.u_inst_mem.mem[2], dut.u_inst_mem.mem[3]);
        if (dut.u_inst_mem.mem[0] !== EXPECTED_IMEM_W0) begin
            $display("TB-ERROR: IMEM[0] = %08h, expected %08h (auipc sp,0x1 from startup.S).",
                     dut.u_inst_mem.mem[0], EXPECTED_IMEM_W0);
            $display("TB-ERROR: inst_mem_program.vh may be stale; regenerate from full_instr.hex (scripts/sw make).");
            $stop;
        end
        $display("TB: IMEM fingerprint OK — baked-in program matches full_instr.hex");

        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        // 调试：前若干拍打印流水线与 DMEM 完成字，便于看取指/跳转/访存
        $display("TB: first 24 cycles trace after reset release");
        for (dbg_cycle = 0; dbg_cycle < 24; dbg_cycle = dbg_cycle + 1) begin
            @(posedge clk);
            $display("TRACE[%0d] id_pc=%08h instr=%08h valid=%0d jump_if=%0d ex_jalr=%0d br=%0d dwen=%0d daddr=%08h dwdata=%08h done=%08h",
                     dbg_cycle, id_pc, instr_out, instr_valid_out,
                     dut.u_core.jump_if, dut.u_core.ex_jalr, dut.u_core.ex_branch_taken,
                     dut.dmem_wen, dut.dmem_addr, dut.dmem_wdata, dmem_read_word(DONE_WORD));
        end

        // 轮询 DONE 字；若程序未写 DONE 或卡在自陷前，会在 MAX_CYCLES 后超时
        i = 0;
        while ((dmem_read_word(DONE_WORD) !== DONE_MAGIC) && (i < MAX_CYCLES)) begin
            @(posedge clk);
            i = i + 1;
        end

        mem_done_ok = (dmem_read_word(DONE_WORD) === DONE_MAGIC);
        if (!mem_done_ok) begin
            $display("\nTIMEOUT: DONE_MAGIC (0x%08h) not seen at DMEM word 0x%03x within %0d cycles",
                     DONE_MAGIC, DONE_WORD, MAX_CYCLES);
            $display("        (No signature checks run — TOTAL below is only this timeout, not %0d tests.)",
                     NUM_SIG_CHECKS);
            $display("DBG: id_pc=%08h instr=%08h instr_valid=%0d ex_pc=%08h ex_instr=%08h",
                     id_pc, instr_out, instr_valid_out, ex_pc_out, ex_instr_out);
            $display("DBG: dmem[DONE]=%08h dmem[SIG0]=%08h", dmem_read_word(DONE_WORD),
                     dmem_read_word(SIG_BASE_WORD + 0));
            $display("DBG: DMEM dump around DONE (word 28..35):");
            for (i = 28; i < 36; i = i + 1)
                $display("  dmem[%0d] (addr 0x%03h) = %08h", i, i*4, dmem_read_word(i));
            $display("DBG: DMEM dump SIG region (word 64..82):");
            for (i = 64; i < 83; i = i + 1)
                $display("  dmem[%0d] (addr 0x%03h) = %08h", i, i*4, dmem_read_word(i));
            fail_count = fail_count + 1;
        end else begin
            // 与 full_instr_test.c 中 emit_sig 顺序一致（算术→分支→JAL/JALR→LW/SW）
            $display("\nDONE seen at cycle %0d — running %0d signature checks vs C model expectations", i,
                     NUM_SIG_CHECKS);

            check_sig(0,  32'd13,        "ADD");
            check_sig(1,  32'd7,         "SUB");
            check_sig(2,  32'd2,         "AND");
            check_sig(3,  32'd11,        "OR");
            check_sig(4,  32'd9,         "XOR");
            check_sig(5,  32'd12,        "SLL");
            check_sig(6,  32'd4,         "SRL");
            check_sig(7,  32'hFFFFFFFC,  "SRA");
            check_sig(8,  32'd1,         "SLT");
            check_sig(9,  32'd1,         "SLTU");
            check_sig(10, 32'd42,        "MUL");
            check_sig(11, 32'h12345000,  "LUI");
            check_sig(12, 32'd4,         "AUIPC_REL");
            check_sig(13, 32'd1,         "BEQ/BNE path");
            check_sig(14, 32'd1,         "BLT path");
            check_sig(15, 32'd1,         "JAL self-check");
            check_sig(16, 32'd1,         "JALR self-check");
            check_sig(17, 32'h11223344,  "LW/SW");
        end

        // TOTAL = pass_count + fail_count；超时分支通常只有 1 次 FAIL（超时本身）
        $display("\n==================================================");
        if (!mem_done_ok) begin
            $display("RESULT: TIMEOUT (program did not finish) — signature checks 0 / %0d", NUM_SIG_CHECKS);
            $display("        PASS=%0d  FAIL=%0d  (TOTAL=%0d counts only the timeout failure)",
                     pass_count, fail_count, pass_count + fail_count);
        end else begin
            $display("RESULT: PASS=%0d  FAIL=%0d  TOTAL=%0d  (expected %0d signature checks)",
                     pass_count, fail_count, pass_count + fail_count, NUM_SIG_CHECKS);
        end
        if (fail_count == 0)
            $display(">>> ALL SYSTEM TESTS PASSED <<<");
        else
            $display(">>> %0d SYSTEM TEST(S) FAILED <<<", fail_count);
        $display("==================================================");

        $stop;
    end

endmodule
