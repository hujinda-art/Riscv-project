`timescale 1ns / 1ps

// tb_sw_lw_raw — 定向验证：SW→LW RAW hazard 通过 DMEM
//
// 配套软件：scripts/sw/tb_sw_lw_raw.S → make -C scripts/sw sw-lw
// 程序：SW 存 0x11223344 到 0x200，LW 读回，写 SIG[17](0x144)，再写 DONE(0x80)。
module tb_sw_lw_raw;
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
    localparam integer MAX_CYCLES = 10000;

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
        $display("tb_sw_lw_raw: SW→LW RAW hazard through DMEM");

        #1;
        imem_hex_plusarg_ok = $value$plusargs("IMEM_HEX=%s", imem_hex_path);
        if (imem_hex_plusarg_ok != 0) begin
            $readmemh(imem_hex_path, dut.u_inst_mem.mem);
            $display("TB: IMEM from plusarg: %0s", imem_hex_path);
        end else begin
            $readmemh("scripts/sw/build/tb_sw_lw_raw.hex", dut.u_inst_mem.mem);
            $display("TB: IMEM default scripts/sw/build/tb_sw_lw_raw.hex");
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
            if (i >= MAX_CYCLES)
                $display("  timeout after %0d cycles", MAX_CYCLES);
        end
        $stop;
    end
endmodule
