`timescale 1ns / 1ps
module register_EX(
    input wire clk,
    input wire rst_n,
    input wire stall,
    input wire flush,
    input wire load_enable,
    input wire store_enable,
    input wire load_success,
    input wire dmem_ready,
    input wire [4:0] rd_in,
    input wire [31:0] rd_ex_result_in,
    input wire [31:0] rd_mem_rdata_in,
    input wire        reg_write_en,    // 仅 reg_write_en=1 时更新 ALU 前递
    output wire [4:0] rd_out,
    output wire [31:0] rd_data_out,
    output wire [4:0] rd_out2,
    output wire [31:0] rd_data_out2,
    output wire [4:0] rd_reg_load_out,
    output wire [31:0] rd_data_load_out,
    output wire load_lock_out,
    output wire store_lock_out,
    output wire load_pending_out,
    output wire mem_stall_req,
    output wire mem_busy_out
);
    parameter   NOP_REG = 5'b00000;
    parameter   NOP_DATA = 32'h00000000;

    // --- 第 1 级（1 条前）---
    reg [4:0] rd_reg;
    reg [31:0] rd_data_reg;
    // --- 第 2 级（2 条前）---
    reg [4:0] rd_reg2;
    reg [31:0] rd_data_reg2;

    reg [4:0] rd_reg_load;
    reg [31:0] rd_data_reg_load;
    reg [31:0] rd_data_load_saved; // load 结果保活，防止后续 mem 操作污染 dmem_rdata

    // --- load / store lock FSM ---
    localparam L_IDLE = 2'b00, L_BUSY = 2'b01, L_RELEASE = 2'b10;
    reg [1:0] lstate;
    reg slock;
    reg first_cycle_in_busy;   // 跳过进入 L_BUSY 首周期内粘滞的 dmem_ready

    // load lock FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lstate               <= L_IDLE;
            first_cycle_in_busy  <= 1'b0;
        end else if (flush) begin
            lstate               <= L_IDLE;
            first_cycle_in_busy  <= 1'b0;
        end else begin
            case (lstate)
                L_IDLE:   if (load_enable && !slock) begin
                    lstate               <= L_BUSY;
                    first_cycle_in_busy  <= 1'b1;
                end
                L_BUSY:   if (load_success && !first_cycle_in_busy) begin
                    lstate               <= L_RELEASE;
                end else begin
                    first_cycle_in_busy  <= 1'b0;
                end
                L_RELEASE: begin
                    lstate               <= L_IDLE;
                end
                default: begin
                    lstate               <= L_IDLE;
                    first_cycle_in_busy  <= 1'b0;
                end
            endcase
        end
    end

    // store lock flag: 仅在 slock 自身置位时由 dmem_ready 清除。
    // 置位条件放宽为 lstate != L_BUSY（L_IDLE 或 L_RELEASE 均可，
    // 因为 L_RELEASE 期间 load 已离开访存阶段，总线空闲）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slock <= 1'b0;
        end else if (flush) begin
            slock <= 1'b0;
        end else if (slock && dmem_ready) begin
            slock <= 1'b0;
        end else if (lstate != L_BUSY && store_enable && !slock) begin
            slock <= 1'b1;
        end else begin
            slock <= slock;
        end
    end

    // rd_reg_load / rd_data_reg_load / rd_data_load_saved
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg_load       <= NOP_REG;
            rd_data_reg_load  <= NOP_DATA;
            rd_data_load_saved <= NOP_DATA;
        end else if (flush) begin
            rd_reg_load       <= NOP_REG;
            rd_data_reg_load  <= NOP_DATA;
            rd_data_load_saved <= NOP_DATA;
        end else begin
            if (load_success) begin
                rd_data_reg_load  <= rd_mem_rdata_in;
                rd_data_load_saved <= rd_mem_rdata_in;
            end else if (load_enable) begin
                rd_reg_load       <= rd_in;
                rd_data_reg_load  <= rd_ex_result_in;
            end
        end
    end

    // ALU 前递：2 级 shift register
    // 非写寄存器指令（store/branch 等）rd_in 为 x0，不应覆盖有用前递数据
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg  <= 5'b0;  rd_data_reg  <= 32'b0;
            rd_reg2 <= 5'b0;  rd_data_reg2 <= 32'b0;
        end else if (flush) begin
            rd_reg  <= 5'b0;  rd_data_reg  <= 32'b0;
            rd_reg2 <= 5'b0;  rd_data_reg2 <= 32'b0;
        end else if (stall) begin
            rd_reg  <= rd_reg;  rd_data_reg  <= rd_data_reg;
            rd_reg2 <= rd_reg2; rd_data_reg2 <= rd_data_reg2;
        end else if (!load_enable && reg_write_en) begin
            rd_reg2 <= rd_reg;           rd_data_reg2 <= rd_data_reg;
            rd_reg  <= rd_in;            rd_data_reg  <= rd_ex_result_in;
        end else begin
            // load 或非写寄存器指令：保持前递状态不变
            rd_reg2 <= rd_reg2;          rd_data_reg2 <= rd_data_reg2;
            rd_reg  <= rd_reg;           rd_data_reg  <= rd_data_reg;
        end
    end

    // mem_busy_out 寄存器输出，消除竞争
    wire [1:0] lstate_next =
        (lstate == L_IDLE && load_enable && !slock) ? L_BUSY :
        (lstate == L_BUSY && load_success)           ? L_RELEASE :
        (lstate == L_RELEASE)                        ? L_IDLE : lstate;
    wire slock_next =
        flush ? 1'b0 :
        (slock && dmem_ready) ? 1'b0 :
        (lstate != L_BUSY && store_enable && !slock) ? 1'b1 : slock;

    reg mem_busy_out_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     mem_busy_out_reg <= 1'b0;
        else if (flush) mem_busy_out_reg <= 1'b0;
        else            mem_busy_out_reg <= (lstate_next == L_BUSY) || slock_next;
    end

    assign rd_out      = rd_reg;
    assign rd_data_out = rd_data_reg;
    assign rd_out2      = rd_reg2;
    assign rd_data_out2 = rd_data_reg2;
    assign rd_reg_load_out = rd_reg_load;
    assign rd_data_load_out = (lstate == L_RELEASE) ? rd_data_load_saved :
                              ((lstate == L_BUSY && dmem_ready && !first_cycle_in_busy) ? rd_mem_rdata_in :
                               rd_data_reg_load);
    assign load_lock_out = (lstate == L_BUSY) || (lstate == L_RELEASE);
    assign store_lock_out = slock;
    assign load_pending_out = (lstate == L_BUSY);
    // L_RELEASE 期间新 load 进入 EX 需要额外 stall，等 lstate 回到 L_IDLE 再跟踪
    assign mem_stall_req = ((lstate == L_BUSY) || slock || (lstate == L_RELEASE && load_enable))
                           && (load_enable || store_enable);
    assign mem_busy_out = mem_busy_out_reg;
endmodule
