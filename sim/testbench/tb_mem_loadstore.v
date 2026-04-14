`timescale 1ns / 1ps

// ============================================================================
// tb_mem_loadstore — 定向验证：SW/LW + 写回 + DONE（无 BLT）
//
// 配套软件：scripts/sw/tb_mem_loadstore.S → make -C scripts/sw tb-mem-hex → build/tb_mem.hex
// 程序行为：lui/addi 构造 0x11223344，写到 0x200，读回，写 SIG[17](0x144)，再写 DONE。
//
// 解读结果：
//   - 本 TB PASS 而 tb_system_soc 仍 FAIL 在 SIG[17]/DONE：问题多半在分支/前递，而非访存口。
//   - 本 TB FAIL：优先查 dmem_valid/ready、EX/MEM 流水、load 数据回写、字节序 mem0..mem3。
//
// TB 与 DMEM：仅在 initial 开头通过 dmem_clear 对 dut.u_data_mem.mem* 做清零（初始化）；
// 运行过程中不层次化写入 RAM；DONE 等待与 TRACE 仅观察 dmem_* 总线，结束后再 dmem_read_word 比对。
// ============================================================================
module tb_mem_loadstore;
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

    soc_top dut (
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

    // 仿真观测：层次化引用 core 内 hazard_ctrl 输出，无需增加 soc_top/core_top 端口。
    // 波形里可加：if_stall / mem_stall / load_use_hazard，或路径 dut.u_core.u_hazard_ctrl.*
    wire if_stall         = dut.u_core.u_hazard_ctrl.if_stall;
    wire mem_stall        = dut.u_core.u_hazard_ctrl.mem_stall;
    wire load_use_hazard  = dut.u_core.u_hazard_ctrl.load_use_hazard;
    wire        ex_is_load          = dut.u_core.u_id_ex.ex_is_load;
    wire [4:0]  forward_rd_in       = dut.u_core.u_ex.forward_rd_in;
    wire [31:0] forward_rd_data_in  = dut.u_core.u_ex.forward_rd_data_in;
    wire if_instr_out = dut.u_core.u_if.instr_out;
    wire id_ex_flush = dut.u_core.u_id_ex.flush;
    wire if_id_flush = dut.u_core.u_if_id.flush;
    wire jump_if = dut.u_core.jump_if;
    // 仿真观测：层次化引用 DMEM 总线握手/地址/数据（仅 TB 使用，不改 RTL 接口）
    wire        dmem_valid_mon = dut.u_core.dmem_valid;
    wire        dmem_wen_mon   = dut.u_core.dmem_wen;
    wire        dmem_ren_mon   = dut.u_core.dmem_ren;
    wire        dmem_ready_mon = dut.u_core.dmem_ready;
    wire [31:0] dmem_addr_mon  = dut.u_core.dmem_addr;
    wire [31:0] dmem_wdata_mon = dut.u_core.dmem_wdata;
    wire [31:0] dmem_rdata_mon = dut.u_core.dmem_rdata;
    // 仿真观测：寄存器堆 a4(x14)/a5(x15) 当前值
    wire [31:0] reg_a4_mon = dut.u_core.u_regfile.regs[14];
    wire [31:0] reg_a5_mon = dut.u_core.u_regfile.regs[15];

    wire [31:0] dmem_data_0x200 = {dut.u_data_mem.mem3[32'h00000200 >> 2], dut.u_data_mem.mem2[32'h00000200 >> 2], dut.u_data_mem.mem1[32'h00000200 >> 2], dut.u_data_mem.mem0[32'h00000200 >> 2]};
    wire [31:0] dmem_data_0x144 = {dut.u_data_mem.mem3[32'h00000144 >> 2], dut.u_data_mem.mem2[32'h00000144 >> 2], dut.u_data_mem.mem1[32'h00000144 >> 2], dut.u_data_mem.mem0[32'h00000144 >> 2]};
    localparam [31:0] DONE_MAGIC = 32'hC001D00D;
    localparam integer DONE_WORD = 32'h00000080 >> 2;
    localparam integer SIG_BASE_WORD = 32'h00000100 >> 2;
    localparam integer WORD_SIG17 = SIG_BASE_WORD + 17;
    localparam [31:0] EXPECT_LW = 32'h11223344;
    localparam integer MAX_CYCLES = 100000;
    // main 首条：lui a4,0x11223（与 tb_fwd 的 li t0,-1 区分）
    localparam [31:0] EXPECTED_IMEM_W4 = 32'h11223737;

    // 运行时仅用总线判定「已向 DONE 槽写入魔术字」，不读层次化 BRAM
    wire tb_dmem_done_write_hit = rst_n && dmem_valid_mon && dmem_ready_mon && dmem_wen_mon
        && (dmem_addr_mon == 32'h00000080) && (dmem_wdata_mon == DONE_MAGIC);

    always #5 clk = ~clk;

    reg [1023:0] imem_hex_path;
    integer imem_hex_plusarg_ok;
    integer i;
    integer wr_cnt;
    integer rd_cnt;
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

    // 仅此任务会写入 data_mem；仅应在 initial 初始化阶段调用一次。
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

    // 仅仿真日志：打印每次握手成功的 DMEM 读写事件，定位 DONE(0x80) 是否被真正写入。
    always @(posedge clk) begin
        if (rst_n && dmem_valid_mon && dmem_ready_mon) begin
            if (dmem_wen_mon) begin
                wr_cnt <= wr_cnt + 1;
                $display("DMEM-WR[%0d] pc=%08h addr=%08h wdata=%08h done_bus_hit=%0d a4=%08h a5=%08h",
                         wr_cnt, id_pc, dmem_addr_mon, dmem_wdata_mon, tb_dmem_done_write_hit,
                         reg_a4_mon, reg_a5_mon);
            end
            if (dmem_ren_mon) begin
                rd_cnt <= rd_cnt + 1;
                $display("DMEM-RD[%0d] pc=%08h addr=%08h rdata=%08h a4=%08h a5=%08h",
                         rd_cnt, id_pc, dmem_addr_mon, dmem_rdata_mon, reg_a4_mon, reg_a5_mon);
            end
        end
    end

    initial begin
        $display("==================================================");
        $display("  tb_mem_loadstore — LW/SW + SIG[17] + DONE (no BLT)");
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
            $display("TB-ERROR: IMEM[4]=%08h expect %08h (tb_mem_loadstore.S main first insn: lui a4).",
                     dut.u_inst_mem.mem[4], EXPECTED_IMEM_W4);
            $display("TB-ERROR: Run:  cd scripts/sw  &&  make mem");
            $display("TB-ERROR: Then add to xsim more_options:  -testplusarg IMEM_HEX=F:/Riscv-project/scripts/sw/build/tb_mem.hex");
            $stop;
        end

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        wr_cnt = 0;
        rd_cnt = 0;

        i = 0;
        // 纯 Verilog：不用 SV 的 break；下一拍再判命中（与原先轮询 mem 等价）
        while (!tb_dmem_done_write_hit && (i < MAX_CYCLES)) begin
            @(posedge clk);
            i = i + 1;
        end

        got_sig  = dmem_read_word(WORD_SIG17);
        got_done = dmem_read_word(DONE_WORD);

        $display("");
        $display("--- Result (mem / LW) ---");
        $display("  cycles=%0d  SIG[17]@0x144 (word %0d) = %08h (expect %08h)", i, WORD_SIG17, got_sig, EXPECT_LW);
        $display("  DONE@0x80 (word %0d)      = %08h (expect %08h)", DONE_WORD, got_done, DONE_MAGIC);
        $display("  REG: a4(x14)=%08h a5(x15)=%08h", reg_a4_mon, reg_a5_mon);

        if ((i < MAX_CYCLES) && (got_done === DONE_MAGIC) && (got_sig === EXPECT_LW)) begin
            $display("RESULT: PASS — mem path and DONE write OK");
        end else begin
            $display("RESULT: FAIL — check load return path, MEM/WB, dmem byte BRAM, valid/ready");
            if (i >= MAX_CYCLES)
                $display("        (timeout after %0d cycles)", MAX_CYCLES);
            $display("DBG: dmem bus valid=%0d wen=%0d ren=%0d ready=%0d addr=%08h wdata=%08h rdata=%08h",
                     dmem_valid_mon, dmem_wen_mon, dmem_ren_mon, dmem_ready_mon,
                     dmem_addr_mon, dmem_wdata_mon, dmem_rdata_mon);
            $display("DBG: write_count=%0d read_count=%0d", wr_cnt, rd_cnt);
            $display("DBG: DMEM around DONE (word 30..34):");
            for (i = 30; i < 35; i = i + 1)
                $display("  dmem[%0d] addr=0x%03h val=%08h", i, i*4, dmem_read_word(i));
            $display("DBG: key words SIG17 and data@0x200:");
            $display("  dmem[SIG17] (0x144) = %08h", dmem_read_word(WORD_SIG17));
            $display("  dmem[0x200]         = %08h", dmem_read_word(32'h00000200 >> 2));
        end
        $display("==================================================");
        $stop;
    end
endmodule
