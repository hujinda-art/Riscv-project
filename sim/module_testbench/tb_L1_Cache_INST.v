`timescale 1ns / 1ps
// ============================================================================
// tb_L1_Cache_INST — L1 指令 Cache（L1_Cache_INST）定向仿真
//
// 验证点：
//   1) 冷启动缺失：首次 imem_req 触发 mem 口连续 4 字 refill，下一拍同址命中返回
//   2) 行内命中：同 cache line 内不同字无需再次 refill
//   3) 同组双路：同 index、不同 tag 的两行均可命中
//   4) 下层非组合 ready：延迟一拍给数，refill 仍能完成
//
// 编译示例（仓库根目录，按工具链调整路径）：
//   iverilog -g2012 -I src/RTL/include -y src/RTL/module/Cache \
//     src/RTL/module/Cache/L1_Cache_INST.v sim/testbench/tb_L1_Cache_INST.v -o sim_icache
//   vvp sim_icache
// ============================================================================
`include "../../src/RTL/include/soc_config.vh"
`include "../../src/RTL/module/Cache/L1_Cache_INST.v"

module tb_L1_Cache_INST;
    // 须覆盖测试地址（如 0x0001_00f0）：字地址可达 0x403c+，不能用 12 位折叠，
    // 否则与 0xf0 等同索引，refill 两行数据相同而 expected_word 仍按全地址计算。
    localparam MEM_WORDS = 32768;
    localparam MEM_WORD_IDX_W = $clog2(MEM_WORDS);

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg  [31:0] imem_addr;
    reg         imem_req;
    wire [31:0] imem_rdata;
    wire        imem_ready;

    wire [31:0] mem_addr;
    wire        mem_req;
    // 快路径：mem_rdata 须与当拍 mem_addr 组合对齐；reg+NBA 会落后一拍，行内 refill 字错位
    wire [31:0] mem_rdata;
    wire        mem_ready;
    reg  [31:0] mem_rdata_reg;
    reg         mem_ready_reg;

    (* ram_style = "distributed" *) reg [31:0] backing [0:MEM_WORDS-1];

    integer err_count;
    integer mem_refill_beats;

    // 可改为 1：下层 always ready；0：mem_ready 在 mem_req 后置位晚 1 拍
    reg mem_fast_ready = 1'b1;

    reg        mem_req_d1;
    reg [31:0] mem_addr_d1;

    always #5 clk = ~clk;

    L1_Cache_INST u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .imem_addr (imem_addr),
        .imem_req  (imem_req),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .mem_addr  (mem_addr),
        .mem_req   (mem_req),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready)
    );

    function automatic [31:0] expected_word(input [31:0] byte_addr);
        reg [31:0] widx;
        begin
            widx = byte_addr >> 2;
            expected_word = {8'h5A ^ widx[7:0], widx[15:8], widx[23:16], widx[31:24]};
        end
    endfunction

    task automatic backing_init;
        integer k;
        begin
            for (k = 0; k < MEM_WORDS; k = k + 1)
                backing[k] = {8'h5A ^ k[7:0], k[15:8], k[23:16], k[31:24]};
        end
    endtask

    // 字索引：mem_addr[MEM_WORD_IDX_W+1:2]，覆盖本 TB 中最大字节地址
    wire [MEM_WORD_IDX_W-1:0] mem_word_idx    = mem_addr[MEM_WORD_IDX_W+1:2];
    wire [MEM_WORD_IDX_W-1:0] mem_word_idx_d1 = mem_addr_d1[MEM_WORD_IDX_W+1:2];

    assign mem_rdata = mem_fast_ready ? backing[mem_word_idx] : mem_rdata_reg;
    assign mem_ready = mem_fast_ready ? mem_req : mem_ready_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_req_d1  <= 1'b0;
            mem_addr_d1 <= 32'b0;
        end else begin
            mem_req_d1  <= mem_req;
            if (mem_req)
                mem_addr_d1 <= mem_addr;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rdata_reg <= 32'b0;
            mem_ready_reg <= 1'b0;
        end else if (!mem_fast_ready) begin
            // mem_ready 较 mem_req 晚一拍，模拟片外存储读延迟
            mem_ready_reg <= mem_req_d1;
            if (mem_req_d1)
                mem_rdata_reg <= backing[mem_word_idx_d1];
        end
    end

    task automatic cpu_fetch(
        input [31:0] addr,
        output [31:0] data,
        input integer max_cycles
    );
        integer cyc;
        reg     aborted;
        begin
            cyc = 0;
            aborted = 1'b0;
            @(posedge clk);
            imem_addr = addr;
            imem_req  = 1'b1;
            while (!imem_ready && !aborted) begin
                @(posedge clk);
                cyc = cyc + 1;
                if (cyc > max_cycles) begin
                    $display("TIMEOUT cpu_fetch addr=%08h after %0d cycles", addr, max_cycles);
                    err_count = err_count + 1;
                    imem_req = 1'b0;
                    data = 32'hdeadbeef;
                    aborted = 1'b1;
                end
            end
            if (!aborted) begin
                data = imem_rdata;
                imem_req = 1'b0;
                @(posedge clk);
            end else
                @(posedge clk);
        end
    endtask

    task automatic check_word(
        input [31:0] addr,
        input [31:0] got,
        input [255:0] tag_ascii
    );
        reg [31:0] expv;
        begin
            expv = expected_word(addr);
            if (got !== expv) begin
                $display("FAIL [%0s] addr=%08h exp=%08h got=%08h", tag_ascii, addr, expv, got);
                err_count = err_count + 1;
            end else
                $display("PASS [%0s] addr=%08h data=%08h", tag_ascii, addr, got);
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && mem_req && mem_ready)
            mem_refill_beats = mem_refill_beats + 1;
    end

    initial begin
        backing_init;
        err_count = 0;
        mem_refill_beats = 0;
        imem_addr = 32'b0;
        imem_req  = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        begin : test_cold_miss_then_hit
            reg [31:0] d0, d1;
            integer beats_before;
            $display("--- 1) cold start ---");
            beats_before = mem_refill_beats;
            cpu_fetch(32'h0000_0100, d0, 80);
            check_word(32'h0000_0100, d0, "cold_line_word0");
            if ((mem_refill_beats - beats_before) != 4) begin
                $display("FAIL: refill beats exp=4 got=%0d", mem_refill_beats - beats_before);
                err_count = err_count + 1;
            end
            beats_before = mem_refill_beats;
            cpu_fetch(32'h0000_0100, d1, 20);
            check_word(32'h0000_0100, d1, "same_addr_hit");
            if ((mem_refill_beats - beats_before) != 0) begin
                $display("FAIL: hit should not refill, mem beats=%0d", mem_refill_beats - beats_before);
                err_count = err_count + 1;
            end
        end

        begin : test_line_words
            reg [31:0] dw;
            $display("--- 2) same line hit ---");
            cpu_fetch(32'h0000_0104, dw, 40);
            check_word(32'h0000_0104, dw, "same_line_word1");
            cpu_fetch(32'h0000_010C, dw, 40);
            check_word(32'h0000_010C, dw, "same_line_word3");
        end

        begin : test_two_ways_same_index
            reg [31:0] da, db;
            $display("--- 3) different set hit---");
            cpu_fetch(32'h0000_00F0, da, 80);
            check_word(32'h0000_00F0, da, "setA_line");
            cpu_fetch(32'h0001_00F0, db, 80);
            check_word(32'h0001_00F0, db, "setB_line");
            cpu_fetch(32'h0000_00F0, da, 40);
            check_word(32'h0000_00F0, da, "setA_hit_after_B");
            cpu_fetch(32'h0001_00F0, db, 40);
            check_word(32'h0001_00F0, db, "setB_hit_after_A");
        end

        begin : test_slow_mem
            reg [31:0] ds;
            integer bb;
            $display("--- 4) slow mem_ready ---");
            mem_fast_ready = 1'b0;
            @(posedge clk);
            bb = mem_refill_beats;
            cpu_fetch(32'h0000_0200, ds, 200);
            check_word(32'h0000_0200, ds, "slow_mem_line");
            if ((mem_refill_beats - bb) != 4) begin
                $display("FAIL slow mem: refill beats exp=4 got=%0d", mem_refill_beats - bb);
                err_count = err_count + 1;
            end
            mem_fast_ready = 1'b1;
            @(posedge clk);
        end

        if (err_count == 0)
            $display("*** tb_L1_Cache_INST ALL PASS ***");
        else
            $display("*** tb_L1_Cache_INST FAIL count=%0d ***", err_count);

        #20;
        $finish;
    end

endmodule
