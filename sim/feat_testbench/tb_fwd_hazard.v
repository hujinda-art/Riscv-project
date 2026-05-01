`timescale 1ns / 1ps

// ============================================================================
// tb_fwd_hazard — 定向验证：EX 前递 + 分支冒险（典型为 BLT），刻意不含 LW/SW 测试路径
//
// 配套软件：scripts/sw/tb_fwd_hazard.S → make -C scripts/sw tb-fwd-hex → build/tb_fwd.hex
// 程序行为：仅执行 li/BLT/写 SIG[14](0x138)=1、再写 DONE(0x80)，最后自陷。
//
// 解读结果：
//   - 本 TB PASS 而 tb_system_soc 仍 FAIL 在 SIG[14]/BLT：问题多半不在纯前递，而在全程序其它交互。
//   - 本 TB FAIL（SIG[14]!=1 或 DONE 未到）：优先查 BLT 比较、前递、flush/stall 与分支相关 RTL。
// ============================================================================
module tb_fwd_hazard;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg stall = 1'b0;
    reg flush = 1'b0;
    reg exception = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg interrupt = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

    wire [31:0] id_pc, id_pc_plus4, instr_out;
    wire instr_valid_out;
    wire [6:0] fun7_out;
    wire [4:0] rs2_out, rs1_out, rd_out;
    wire [2:0] fuc3_out;
    wire [6:0] opcode_out;
    wire [31:0] ex_pc_out, ex_pc_plus4_out, ex_instr_out, ex_imm_out;
    wire ex_instr_valid_out;
    wire [31:0] ex_result_out, ex_mem_addr_out, ex_mem_wdata_out;

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

    localparam [31:0] DONE_MAGIC = 32'hC001D00D;
    localparam integer DONE_WORD = 32'h00000080 >> 2;
    localparam integer SIG_BASE_WORD = 32'h00000100 >> 2;
    localparam integer WORD_SIG14 = SIG_BASE_WORD + 14;
    localparam integer MAX_CYCLES = 100000;
    // main 首条：li t0,-1（与 full_instr 的 li t0,10 区分，用于检测 hex 是否加载）
    localparam [31:0] EXPECTED_IMEM_W4 = 32'hFF000293;

    reg [1023:0] imem_hex_path;
    integer imem_hex_plusarg_ok;
    integer i;
    reg [31:0] got_sig;
    reg [31:0] got_done;

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

    task dmem_clear;
        integer j;
        begin
            for (j = 0; j < 1024; j = j + 1) begin
                dut.u_data_mem.mem0[j] = 8'h00;
                dut.u_data_mem.mem1[j] = 8'h00;
                dut.u_data_mem.mem2[j] = 8'h00;
                dut.u_data_mem.mem3[j] = 8'h00;
            end
        end
    endtask

    initial begin
        $display("==================================================");
        $display("  tb_fwd_hazard — BLT + SIG[14] only (no LW/SW test)");
        $display("==================================================");

        rst_n = 1'b0;
        dmem_clear;

        // 与 tb_system_soc 保持一致：仿真选项里用 -testplusarg IMEM_HEX=<绝对路径>
        // 若未提供，则保留 inst_mem 当前镜像；随后用 IMEM 指纹判断是否真加载到目标程序。
        imem_hex_plusarg_ok = $value$plusargs("IMEM_HEX=%s", imem_hex_path);
        if (imem_hex_plusarg_ok != 0) begin
            $display("TB: overriding IMEM from plusarg IMEM_HEX: %s", imem_hex_path);
            $readmemh(imem_hex_path, dut.u_inst_mem.mem);
        end else begin
            $display("TB: no IMEM_HEX given; keeping current inst_mem image");
        end

        #1;
        if (dut.u_inst_mem.mem[4] !== EXPECTED_IMEM_W4) begin
            $display("TB-ERROR: IMEM[4]=%08h expect %08h (tb_fwd_hazard.S main first insn: li t0,-1).",
                     dut.u_inst_mem.mem[4], EXPECTED_IMEM_W4);
            $display("TB-ERROR: Run:  cd scripts/sw  &&  make fwd");
            $display("TB-ERROR: Then add to xsim more_options:  -testplusarg IMEM_HEX=F:/Riscv-project/scripts/sw/build/tb_fwd.hex");
            $stop;
        end

        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        i = 0;
        while ((dmem_read_word(DONE_WORD) !== DONE_MAGIC) && (i < MAX_CYCLES)) begin
            @(posedge clk);
            i = i + 1;
        end

        got_sig  = dmem_read_word(WORD_SIG14);
        got_done = dmem_read_word(DONE_WORD);

        $display("");
        $display("--- Result (forwarding / BLT) ---");
        $display("  cycles=%0d  SIG[14]@0x138 (word %0d) = %08h (expect 1)", i, WORD_SIG14, got_sig);
        $display("  DONE@0x80 (word %0d)      = %08h (expect %08h)", DONE_WORD, got_done, DONE_MAGIC);

        if ((got_done === DONE_MAGIC) && (got_sig === 32'd1)) begin
            $display("RESULT: PASS — forwarding/BLT path and DONE write OK");
        end else begin
            $display("RESULT: FAIL — if SIG[14]!=1 check BLT, EX forwarding, flush; if DONE missing check store/WB");
            if (i >= MAX_CYCLES)
                $display("        (timeout after %0d cycles)", MAX_CYCLES);
        end
        $display("==================================================");
        $stop;
    end
endmodule
