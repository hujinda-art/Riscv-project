`timescale 1ns / 1ps
//
// special_features_tb.v  -- Special Feature Verification Testbench
//
// Validates 7 design features unique to this CPU vs a standard 5-stage pipeline:
//
//  T1: JAL resolved in IF/ID stage (not EX). PC redirected 1 cycle earlier.
//      Link register written via write-port-2 (jal_link_we) in the same cycle.
//
//  T2: JALR writes rd = PC+4 (return address), NOT the jump target address.
//      (Corresponds to CHANGE_REPORT Bug 4 fix)
//
//  T3: Load-use hazard + custom load-lock forwarding (register_EX / register_MEM).
//      A 2-stage shift chain in register_MEM aligns data to synchronous memory timing.
//
//  T4: register_EX normal ALU forwarding chain (consecutive dependent ALU ops).
//      Verifies the rd_reg / rd_data_reg forwarding path.
//
//  T5: Dual write-back paths (EX_WB_reg and MEM_WB_reg).
//      WB_stage selects address and data based on wb_is_load_in.
//
//  T6: Branch resolved in EX stage; flush covers only IF/ID + ID/EX.
//      Instructions in EX/MEM and later are NOT flushed.
//
//  T7: JAL write-port-2 (jal_link_we) overrides WB write-port-1 on same rd
//      in the same clock cycle (port-2 executes last in the always block).
//
// ============================================================

module tb_special_features;

    // --------------------------------------------------------
    // DUT ports
    // --------------------------------------------------------
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

    soc_top_bram dut (
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

    // DEBUG: monitor EX stage
    always @(posedge clk) begin
        if (rst_n) begin
            $display("DEBUG EX @%0t: pc=%08h valid=%b rd=%0d result=%08h opcode=%07b load=%b store=%b lockL=%b",
                     $time, dut.u_core.ex_pc_out, dut.u_core.ex_instr_valid_out,
                     dut.u_core.rd_out, dut.u_core.ex_result_out, dut.u_core.opcode_out,
                     dut.u_core.ex_is_load, dut.u_core.ex_is_store, dut.u_core.load_lock_out);
        end
    end

    // DEBUG: monitor WB stage every cycle
    always @(posedge clk) begin
        if (rst_n) begin
            $display("DEBUG WB @%0t: we=%b waddr=%0d wdata=%08h is_load=%b rd_ex=%0d result_ex=%08h rd_mem=%0d data_mem=%08h",
                     $time, dut.u_core.wb_we_out, dut.u_core.wb_waddr_out, dut.u_core.wb_wdata_out,
                     dut.u_core.wb_is_load_out, dut.u_core.wb_rd_out_ex, dut.u_core.wb_result_out,
                     dut.u_core.wb_rd_out_mem, dut.u_core.wb_load_data_out);
        end
    end

    // --------------------------------------------------------
    // Pass / fail counters
    // --------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------
    // Register check helper
    // --------------------------------------------------------
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

    // --------------------------------------------------------
    // Reset + clear memories + clear register file
    // Must be called before every test to ensure state isolation.
    //
    // IMPORTANT: do NOT call @(posedge clk) after rst_n=1 here.
    // After rst_n goes high, pc_current is still 0x00 (async reset).
    // The caller must write instructions to mem[] BEFORE the first
    // posedge of repeat(N), so that IF/ID captures mem[0] correctly
    // at that first posedge.
    // --------------------------------------------------------
    task do_reset;
        integer i;
        begin
            rst_n = 0;
            // Fill instruction memory with NOP (addi x0, x0, 0)
            for (i = 0; i < 1024; i = i + 1)
                dut.u_inst_mem.mem[i] = 32'h00000013;
            // Zero out data memory
            for (i = 0; i < 1024; i = i + 1) begin
                dut.u_data_mem.mem0[i] = 8'h00;
                dut.u_data_mem.mem1[i] = 8'h00;
                dut.u_data_mem.mem2[i] = 8'h00;
                dut.u_data_mem.mem3[i] = 8'h00;
            end
            // Zero out register file (x0 is hardwired 0; clear x1-x31 for isolation)
            for (i = 1; i < 32; i = i + 1)
                dut.u_core.u_regfile.regs[i] = 32'h00000000;
            // Hold reset for 2 cycles to drain the pipeline
            repeat(2) @(posedge clk);
            rst_n = 1;
            // NO posedge here - PC stays at 0x00 until the caller's repeat(N)
        end
    endtask

    `define REGS dut.u_core.u_regfile.regs

    // ============================================================
    initial begin
        $display("==================================================");
        $display("  Special Feature Verification Testbench");
        $display("==================================================");

        // ========================================================
        // TEST 1: Early JAL resolution in IF/ID stage
        //
        // Normal 5-stage pipeline resolves JAL in EX (2-cycle flush).
        // This CPU detects JAL in IF/ID, redirects PC in the same
        // cycle, and writes rd=PC+4 via write-port-2 (jal_link_we).
        //
        // Program:
        //   0x00: addi x1, x0, 5       x1 = 5
        //   0x04: jal  x2, +8          x2 = 0x08 (PC+4), jump to 0x0C
        //   0x08: addi x3, x0, 99      [SQUASH - must NOT execute]
        //   0x0C: addi x4, x0, 7       [TARGET - must execute]
        // ========================================================
        $display("\n--- TEST 1: Early JAL in IF/ID + rd = PC+4 ---");
        #1;
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00500093; // addi x1, x0, 5
        dut.u_inst_mem.mem[1] = 32'h0080016F; // jal  x2, +8
        dut.u_inst_mem.mem[2] = 32'h06300193; // addi x3, x0, 99  [SQUASH]
        dut.u_inst_mem.mem[3] = 32'h00700213; // addi x4, x0, 7   [TARGET 0x0C]

        repeat(40) @(posedge clk);
        check_eq(`REGS[1], 32'd5,  "T1 addi    x1=5          ");
        check_eq(`REGS[2], 32'h08, "T1 JAL-lnk x2=0x08(PC+4)");
        check_eq(`REGS[3], 32'd0,  "T1 squash  x3=0          ");
        check_eq(`REGS[4], 32'd7,  "T1 target  x4=7          ");

        // ========================================================
        // TEST 2: JALR writes rd = PC+4 (return address, not target)
        //
        // RISC-V spec: JALR stores PC+4 in rd; jump target only
        // affects the PC.  (Fixes CHANGE_REPORT Bug 4: original code
        // stored pc_jalr instead of ex_pc_plus4.)
        //
        // Program:
        //   0x00: addi x1, x0, 12      x1 = 0x0C (base for JALR)
        //   0x04: jalr x2, x1, 0       x2 = PC+4 = 0x08; PC = 0x0C
        //   0x08: addi x5, x0, 99      [SQUASH]
        //   0x0C: addi x3, x0, 7       [TARGET]
        // ========================================================
        $display("\n--- TEST 2: JALR rd = PC+4 (not jump target) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00C00093; // addi x1, x0, 12
        dut.u_inst_mem.mem[1] = 32'h00008167; // jalr x2, x1, 0
        dut.u_inst_mem.mem[2] = 32'h06300293; // addi x5, x0, 99  [SQUASH]
        dut.u_inst_mem.mem[3] = 32'h00700193; // addi x3, x0, 7   [TARGET 0x0C]

        repeat(40) @(posedge clk);
        check_eq(`REGS[2], 32'h08, "T2 JALR-lnk x2=0x08     ");
        check_eq(`REGS[3], 32'd7,  "T2 target   x3=7         ");
        check_eq(`REGS[5], 32'd0,  "T2 squash   x5=0         ");

        // ========================================================
        // TEST 3: Load-use hazard + register_EX/register_MEM lock
        //
        // Unlike a standard forwarding unit, this CPU uses:
        //   register_EX  - holds the load destination + data
        //   register_MEM - 2-stage shift chain that aligns the
        //                  synchronous memory read timing
        // load_use_hazard inserts 1 bubble; after data returns,
        // register_EX forwards the value to the next EX stage.
        //
        // Program:
        //   0x00: addi x1, x0, 100     x1 = 100
        //   0x04: sw   x1, 0(x0)       mem[0] = 100
        //   0x08: nop
        //   0x0C: lw   x2, 0(x0)       x2 = 100
        //   0x10: addi x3, x2, 1       x3 = 101  [load-use: needs forwarded x2]
        //   0x14: addi x4, x3, 0       x4 = 101  [normal forward x3]
        // ========================================================
        $display("\n--- TEST 3: Load-use hazard + custom load-lock forwarding ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h06400093; // addi x1, x0, 100
        dut.u_inst_mem.mem[1] = 32'h00102023; // sw   x1, 0(x0)
        dut.u_inst_mem.mem[2] = 32'h00000013; // nop
        dut.u_inst_mem.mem[3] = 32'h00002103; // lw   x2, 0(x0)
        dut.u_inst_mem.mem[4] = 32'h00110193; // addi x3, x2, 1
        dut.u_inst_mem.mem[5] = 32'h00018213; // addi x4, x3, 0

        repeat(20) @(posedge clk);
        check_eq(`REGS[2], 32'd100, "T3 lw        x2=100      ");
        check_eq(`REGS[3], 32'd101, "T3 load-use  x3=101      ");
        check_eq(`REGS[4], 32'd101, "T3 chain-fwd x4=101      ");

        // ========================================================
        // TEST 4: Consecutive ALU forwarding chain via register_EX
        //
        // register_EX updates rd_reg/rd_data_reg immediately after
        // each non-load instruction, enabling back-to-back forwarding
        // with zero extra bubbles.
        //
        // Program:
        //   0x00: addi x1, x0, 10      x1 = 10
        //   0x04: addi x2, x1, 5       x2 = 15  [forward x1]
        //   0x08: add  x3, x2, x1      x3 = 25  [forward x2 and x1]
        //   0x0C: add  x4, x3, x2      x4 = 40  [forward x3 and x2]
        // ========================================================
        $display("\n--- TEST 4: Consecutive ALU forwarding (register_EX path) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00A00093; // addi x1, x0, 10
        dut.u_inst_mem.mem[1] = 32'h00508113; // addi x2, x1, 5
        dut.u_inst_mem.mem[2] = 32'h001101B3; // add  x3, x2, x1
        dut.u_inst_mem.mem[3] = 32'h00218233; // add  x4, x3, x2

        repeat(40) @(posedge clk);
        check_eq(`REGS[1], 32'd10, "T4 x1=10             ");
        check_eq(`REGS[2], 32'd15, "T4 x2=15             ");
        check_eq(`REGS[3], 32'd25, "T4 x3=25             ");
        check_eq(`REGS[4], 32'd40, "T4 x4=40             ");

        // ========================================================
        // TEST 5: Dual write-back paths (EX_WB_reg vs MEM_WB_reg)
        //
        // ALU results travel: EX -> EX_WB_reg -> WB_stage (port-1).
        // Load results travel: EX -> EX/MEM -> MEM_WB_reg -> WB_stage.
        // WB_stage selects address and data based on wb_is_load_in.
        //
        // Program:
        //   0x00: addi x1, x0, 42      x1 = 42  (via EX_WB_reg)
        //   0x04: sw   x1, 0(x0)       mem[0] = 42
        //   0x08, 0x0C: nop x2
        //   0x10: lw   x2, 0(x0)       x2 = 42  (via MEM_WB_reg)
        //   0x14~0x1C: nop x3
        //   0x20: add  x3, x1, x2      x3 = 84
        // ========================================================
        $display("\n--- TEST 5: Dual WB paths (EX_WB_reg vs MEM_WB_reg) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h02A00093; // addi x1, x0, 42
        dut.u_inst_mem.mem[1] = 32'h00102023; // sw   x1, 0(x0)
        dut.u_inst_mem.mem[2] = 32'h00000013; // nop
        dut.u_inst_mem.mem[3] = 32'h00000013; // nop
        dut.u_inst_mem.mem[4] = 32'h00002103; // lw   x2, 0(x0)
        dut.u_inst_mem.mem[5] = 32'h00000013; // nop
        dut.u_inst_mem.mem[6] = 32'h00000013; // nop
        dut.u_inst_mem.mem[7] = 32'h00000013; // nop
        dut.u_inst_mem.mem[8] = 32'h002081B3; // add  x3, x1, x2

        repeat(60) @(posedge clk);
        check_eq(`REGS[1], 32'd42, "T5 EX_WB  x1=42      ");
        check_eq(`REGS[2], 32'd42, "T5 MEM_WB x2=42      ");
        check_eq(`REGS[3], 32'd84, "T5 sum    x3=84      ");

        // ========================================================
        // TEST 6: Branch resolved in EX; flush covers only IF/ID + ID/EX
        //
        // branch_hazard_ex = ex_branch_taken | ex_jalr.
        // Flushes IF/ID and ID/EX only; instructions already in
        // EX/MEM or later are on the correct path and must complete.
        //
        // Program:
        //   0x00: addi x1, x0, 5
        //   0x04: addi x2, x0, 5
        //   0x08: beq  x1, x2, +12    taken -> jump to 0x14
        //   0x0C: addi x3, x0, 99     [SQUASH]
        //   0x10: addi x3, x0, 98     [SQUASH]
        //   0x14: addi x4, x0, 7      [TARGET]
        // ========================================================
        $display("\n--- TEST 6: Branch flush covers only IF/ID + ID/EX ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h00500093; // addi x1, x0, 5
        dut.u_inst_mem.mem[1] = 32'h00500113; // addi x2, x0, 5
        dut.u_inst_mem.mem[2] = 32'h00208663; // beq  x1, x2, +12
        dut.u_inst_mem.mem[3] = 32'h06300193; // addi x3, x0, 99  [SQUASH]
        dut.u_inst_mem.mem[4] = 32'h06200193; // addi x3, x0, 98  [SQUASH]
        dut.u_inst_mem.mem[5] = 32'h00700213; // addi x4, x0, 7   [TARGET 0x14]

        repeat(40) @(posedge clk);
        check_eq(`REGS[3], 32'd0, "T6 squash x3=0       ");
        check_eq(`REGS[4], 32'd7, "T6 target x4=7       ");

        // ========================================================
        // TEST 7: JAL write-port-2 overrides WB write-port-1 (same rd)
        //
        // When JAL is in IF/ID (port-2 active) and a prior instruction
        // WB (port-1) targets the same rd in the SAME clock edge,
        // register.v executes port-2 last so the JAL link value wins.
        //
        // Timing alignment (no stalls):
        //   JAL at 0x08 is in IF/ID at the same posedge that
        //   addi x1 (at 0x00, 2 instructions earlier) reaches WB.
        //
        // Program:
        //   0x00: addi x1, x0, 99     WB fires same edge as JAL link write
        //   0x04: nop                 spacing to align the two writes
        //   0x08: jal  x1, +8         jal_link writes x1=0x0C, overrides WB
        //   0x0C: addi x5, x0, 55     [SQUASH]
        //   0x10: addi x2, x0, 1      [TARGET 0x10]
        //
        // Expected: x1=0x0C (JAL link wins), x5=0, x2=1
        // ========================================================
        $display("\n--- TEST 7: JAL port-2 overrides WB port-1 (same rd, same cycle) ---");
        do_reset;
        dut.u_inst_mem.mem[0] = 32'h06300093; // addi x1, x0, 99
        dut.u_inst_mem.mem[1] = 32'h00000013; // nop
        dut.u_inst_mem.mem[2] = 32'h008000EF; // jal  x1, +8 (target=0x10, link=0x0C)
        dut.u_inst_mem.mem[3] = 32'h03700293; // addi x5, x0, 55  [SQUASH]
        dut.u_inst_mem.mem[4] = 32'h00100113; // addi x2, x0, 1   [TARGET 0x10]

        repeat(40) @(posedge clk);
        check_eq(`REGS[1], 32'h0C, "T7 JAL-lnk x1=0x0C  ");
        check_eq(`REGS[5], 32'd0,  "T7 squash  x5=0      ");
        check_eq(`REGS[2], 32'd1,  "T7 target  x2=1      ");

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

        $stop;
    end

endmodule
