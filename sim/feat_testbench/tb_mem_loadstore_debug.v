`timescale 1ns / 1ps

// tb_mem_loadstore_debug.v
// 目的：像 tb_jump_no_mem 一样做细粒度定位，明确 LW/SW/写回链路具体在哪一环失败。
// 场景：无分支复杂路径，固定程序如下：
//   0x10: lui  x14, 0x11223
//   0x14: addi x14, x14, 0x344      -> x14 = 0x11223344
//   0x18: addi x15, x0, 0x200       -> x15 = 0x200
//   0x1C: sw   x14, 0(x15)          -> MEM[0x200] = 0x11223344
//   0x20: lw   x15, 0(x15)          -> x15 = 0x11223344
//   0x24: sw   x15, 0x144(x0)       -> SIG[17] = 0x11223344
//   0x28: lui  x15, 0xC001D
//   0x2C: addi x15, x15, 13         -> x15 = 0xC001D00D
//   0x30: sw   x15, 0x80(x0)        -> DONE = 0xC001D00D
//   0x34: jal  x0, 0                -> 自循环，防止跑飞

module tb_mem_loadstore_debug;
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

    localparam [31:0] EXPECT_WORD = 32'h11223344;
    localparam [31:0] DONE_MAGIC  = 32'hC001D00D;
    localparam integer WORD_0X200 = 32'h00000200 >> 2;
    localparam integer WORD_SIG17 = 32'h00000144 >> 2;
    localparam integer WORD_DONE  = 32'h00000080 >> 2;

    integer errors = 0;
    integer i;
    reg seen_lw_req = 1'b0;
    reg seen_lw_resp = 1'b0;
    reg seen_wb_x15 = 1'b0;
    reg seen_sig_store = 1'b0;
    reg seen_lw_id = 1'b0;
    reg seen_lw_ex = 1'b0;
    reg seen_lw_exmem = 1'b0;

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

    // 关键链路观测：
    // 1) lw 是否发起读请求
    // 2) dmem 是否返回读数据
    // 3) WB 是否把数据写回 x15
    // 4) SIG[17] 写入时 wdata 是多少
    always @(posedge clk) begin
        if (rst_n) begin
            if (!seen_lw_id && instr_valid_out && (instr_out == 32'h0007A783)) begin
                seen_lw_id <= 1'b1;
                $display("TRACE: LW_ID   pc=%08h instr=%08h stall_idex=%b mem_stall_req=%b",
                         id_pc, instr_out, dut.u_core.stall_idex, dut.u_core.mem_stall_req);
            end

            if (!seen_lw_ex && dut.u_core.ex_instr_valid_out && (dut.u_core.ex_instr_out == 32'h0007A783)) begin
                seen_lw_ex <= 1'b1;
                $display("TRACE: LW_EX   pc=%08h ex_is_load=%b mem_read_en=%b lockL=%b lockS=%b",
                         dut.u_core.ex_pc_out, dut.u_core.ex_is_load, dut.u_core.ex_mem_ren,
                         dut.u_core.load_lock_out, dut.u_core.store_lock_out);
            end

            if (!seen_lw_exmem && dut.u_core.exmem_mem_read_en_out && (dut.u_core.exmem_rd_out == 5'd15)) begin
                seen_lw_exmem <= 1'b1;
                $display("TRACE: LW_EXMEM addr=%08h rd=%0d dmem_ready=%b",
                         dut.u_core.exmem_mem_addr_out, dut.u_core.exmem_rd_out, dut.u_core.dmem_ready);
            end

            if (!seen_lw_req && dut.u_core.dmem_ren && dut.u_core.dmem_valid &&
                (dut.u_core.dmem_addr == 32'h00000200)) begin
                seen_lw_req <= 1'b1;
                $display("TRACE: LW_REQ  pc=%08h ex_instr=%08h addr=%08h",
                         id_pc, ex_instr_out, dut.u_core.dmem_addr);
            end

            if (!seen_lw_resp && dut.u_core.dmem_ren && dut.u_core.dmem_ready &&
                (dut.u_core.dmem_addr == 32'h00000200)) begin
                seen_lw_resp <= 1'b1;
                $display("TRACE: LW_RESP pc=%08h dmem_rdata=%08h rd_data_load_out=%08h",
                         id_pc, dut.u_core.dmem_rdata, dut.u_core.rd_data_load_out);
            end

            if (!seen_wb_x15 && dut.u_core.wb_we_out && (dut.u_core.wb_waddr_out == 5'd15)) begin
                seen_wb_x15 <= 1'b1;
                $display("TRACE: WB_X15  pc=%08h wb_wdata=%08h wb_is_load=%b",
                         id_pc, dut.u_core.wb_wdata_out, dut.u_core.wb_is_load_out);
            end

            if (!seen_sig_store && dut.u_core.dmem_wen && dut.u_core.dmem_valid &&
                (dut.u_core.dmem_addr == 32'h00000144)) begin
                seen_sig_store <= 1'b1;
                $display("TRACE: SIG_SW  pc=%08h wdata=%08h", id_pc, dut.u_core.dmem_wdata);
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            $display("CYCLE: dmem_valid=%b dmem_ren=%b dmem_wen=%b addr=%08h wdata=%08h rdata=%08h ready=%b exmem_ren=%b exmem_wen=%b exmem_wen_in=%b stall_idex=%b flush_idex=%b lock_state=%b load_lock=%b store_lock=%b mem_busy=%b",
                     dut.dmem_valid, dut.dmem_ren, dut.dmem_wen, dut.dmem_addr, dut.dmem_wdata,
                     dut.dmem_rdata, dut.dmem_ready,
                     dut.u_core.exmem_mem_read_en_out, dut.u_core.u_exmem.mem_mem_write_en_out,
                     dut.u_core.ex_mem_wen, dut.u_core.stall_idex, dut.u_core.flush_idex,
                     dut.u_core.u_register_ex.lstate, dut.u_core.load_lock_out, dut.u_core.store_lock_out,
                     dut.u_core.u_register_ex.mem_busy_out);
        end
    end

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

    task check_reg;
        input [4:0] regno;
        input [31:0] expected;
        input [255:0] msg;
        reg [31:0] got;
        begin
            got = dut.u_core.u_regfile.regs[regno];
            if (got !== expected) begin
                $display("FAIL: %s reg[%0d]=%08h (expected %08h)", msg, regno, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %s", msg);
            end
        end
    endtask

    task check_mem_word;
        input integer wi;
        input [31:0] expected;
        input [255:0] msg;
        reg [31:0] got;
        begin
            got = dmem_read_word(wi);
            if (got !== expected) begin
                $display("FAIL: %s mem[%0d]=%08h (expected %08h)", msg, wi, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %s", msg);
            end
        end
    endtask

    initial begin
        #1;
        // 清空数据存储器
        for (i = 0; i < 1024; i = i + 1) begin
            dut.u_data_mem.mem0[i] = 8'h00;
            dut.u_data_mem.mem1[i] = 8'h00;
            dut.u_data_mem.mem2[i] = 8'h00;
            dut.u_data_mem.mem3[i] = 8'h00;
        end

        // 先把 IMEM 填成 NOP，避免跑到旧程序
        for (i = 0; i < 1024; i = i + 1) begin
            dut.u_inst_mem.mem[i] = 32'h00000013;
        end

        // 启动段（保持与 tb_mem.hex 一致）
        dut.u_inst_mem.mem[0]  = 32'h00001117; // auipc sp,0x1
        dut.u_inst_mem.mem[1]  = 32'h00010113; // addi  sp,sp,0
        dut.u_inst_mem.mem[2]  = 32'h008000EF; // jal   ra,+8 -> 0x10
        dut.u_inst_mem.mem[3]  = 32'h0000006F; // jal   x0,0

        // 主测试段
        dut.u_inst_mem.mem[4]  = 32'h11223737; // lui   x14,0x11223
        dut.u_inst_mem.mem[5]  = 32'h34470713; // addi  x14,x14,0x344
        dut.u_inst_mem.mem[6]  = 32'h20000793; // addi  x15,x0,0x200
        dut.u_inst_mem.mem[7]  = 32'h00E7A023; // sw    x14,0(x15)
        dut.u_inst_mem.mem[8]  = 32'h0007A783; // lw    x15,0(x15)
        dut.u_inst_mem.mem[9]  = 32'h14F02223; // sw    x15,0x144(x0)
        dut.u_inst_mem.mem[10] = 32'hC001D7B7; // lui   x15,0xC001D
        dut.u_inst_mem.mem[11] = 32'h00D78793; // addi  x15,x15,13
        dut.u_inst_mem.mem[12] = 32'h08F02023; // sw    x15,0x80(x0)
        dut.u_inst_mem.mem[13] = 32'h0000006F; // jal   x0,0 (self-loop)

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // 给足周期覆盖完整路径
        repeat (220) @(posedge clk);

        $display("\n========== Mem-LoadStore Debug Results ==========");
        $display("TRACE_SUMMARY: lw_id=%0b lw_ex=%0b lw_exmem=%0b lw_req=%0b lw_resp=%0b wb_x15=%0b sig_store=%0b",
                 seen_lw_id, seen_lw_ex, seen_lw_exmem, seen_lw_req, seen_lw_resp, seen_wb_x15, seen_sig_store);
        check_reg(14, EXPECT_WORD, "R1 x14 should be 0x11223344");
        check_reg(15, DONE_MAGIC,  "R2 x15 should end at DONE_MAGIC");
        check_mem_word(WORD_0X200, EXPECT_WORD, "M1 MEM[0x200] store result");
        check_mem_word(WORD_SIG17, EXPECT_WORD, "M2 SIG[17] from lw result");
        check_mem_word(WORD_DONE, DONE_MAGIC,   "M3 DONE magic word");

        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d TEST(S) FAILED ***", errors);
        $display("===============================================\n");
        $stop;
    end
endmodule

