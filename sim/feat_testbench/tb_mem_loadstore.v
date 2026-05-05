`timescale 1ns / 1ps

// ============================================================================
// tb_mem_loadstore — 定向验证：SW/LW + 写回 + DONE（无 BLT）
//
// 配套软件：scripts/sw/tb_mem_loadstore.S → make -C scripts/sw tb-mem-hex
// 程序：lui/addi 构造 0x11223344，写 0x200，读回，写 SIG[17](0x144)，再写 DONE(0x80)。
//
// initial：#1 后用 $readmemh 加载 IMEM（默认 scripts/sw/build/tb_mem.hex，可用 +IMEM_HEX=路径 覆盖）；
// 须晚于 inst_mem 内 initial，否则会与 inst_mem_program.vh 初始化顺序竞争。
// 模块内 wire * _mon 等供波形抓取。
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

    localparam [31:0] DONE_MAGIC = 32'hC001D00D;
    localparam integer DONE_WORD = 32'h00000080 >> 2;
    localparam integer SIG_BASE_WORD = 32'h00000100 >> 2;
    localparam integer WORD_SIG17 = SIG_BASE_WORD + 17;
    localparam [31:0] EXPECT_LW = 32'h11223344;
    localparam integer MAX_CYCLES = 100000;

    // DONE 写入可能发生在 debug 循环期间，需用锁存器捕捉，避免 while 循环错过。
    reg tb_done_hit;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tb_done_hit <= 1'b0;
        else if (dut.dmem_valid && dut.dmem_wen
                 && (dut.dmem_addr == 32'h00000080)
                 && (dut.dmem_wdata == DONE_MAGIC))
            tb_done_hit <= 1'b1;
    end


    always #5 clk = ~clk;

    integer i;
    reg [31:0] got_sig;
    reg [31:0] got_done;
    reg [1023:0] imem_hex_path;
    integer      imem_hex_plusarg_ok;

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
        $display("tb_mem_loadstore: LW/SW + SIG[17] + DONE");

        // 晚一拍加载，避免与 inst_mem initial（inst_mem_program.vh）在同一 time slot 顺序不定
        #1;
        imem_hex_plusarg_ok = $value$plusargs("IMEM_HEX=%s", imem_hex_path);
        if (imem_hex_plusarg_ok != 0) begin
            $readmemh(imem_hex_path, dut.u_inst_mem.mem);
            $display("TB: IMEM from plusarg IMEM_HEX: %0s", imem_hex_path);
        end else begin
            $readmemh("scripts/sw/build/tb_mem.hex", dut.u_inst_mem.mem);
            $display("TB: IMEM default ../../scripts/sw/build/tb_mem.hex (override: +IMEM_HEX=<path>)");
        end

        rst_n = 1'b0;
        dmem_clear;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        i = 0;
        while (!tb_done_hit && (i < MAX_CYCLES)) begin
            @(posedge clk);
            i = i + 1;
        end

        got_sig  = dmem_read_word(WORD_SIG17);
        got_done = dmem_read_word(DONE_WORD);

        $display("  cycles=%0d  SIG[17]=%08h (exp %08h)  DONE=%08h (exp %08h)",
                 i, got_sig, EXPECT_LW, got_done, DONE_MAGIC);

        if ((i < MAX_CYCLES) && (got_done === DONE_MAGIC) && (got_sig === EXPECT_LW))
            $display("RESULT: PASS");
        else begin
            $display("RESULT: FAIL");
            if (i >= MAX_CYCLES) begin
                $display("  timeout after %0d cycles", MAX_CYCLES);
                $display("  DBG: id_pc=%08h instr=%08h ex_pc=%08h ex_instr=%08h",
                         id_pc, instr_out, ex_pc_out, ex_instr_out);
            end
        end
        $stop;
    end
endmodule
