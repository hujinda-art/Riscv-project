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
    output wire load_skip_stale_out,
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
    reg first_cycle_in_busy;   // load 还未在其 EX/MEM 周期内接收到真正的 dmem_ready
    reg dmem_ready_d1;         // 上一拍的 dmem_ready，用于判断进入 EX/MEM 时 ready 是否粘滞

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dmem_ready_d1 <= 1'b0;
        else
            dmem_ready_d1 <= dmem_ready;
    end

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
                L_IDLE:   if (load_enable) begin
                    lstate               <= L_BUSY;
                    first_cycle_in_busy  <= 1'b1;
                end
                L_BUSY:   if (load_success && (!first_cycle_in_busy || !dmem_ready_d1)) begin
                    lstate <= L_RELEASE;
                end else if (load_success && first_cycle_in_busy && dmem_ready_d1) begin
                    // stale ready：跳过，first_cycle_in_busy 清零后等待 data_mem 真实 ready
                    first_cycle_in_busy <= 1'b0;
                end else if (!first_cycle_in_busy && dmem_ready && !load_success) begin
                    // 跳过 stale 后，data_mem 的真实 ready 到达（load 已流出 EX/MEM，load_success=0）
                    lstate <= L_RELEASE;
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
            end else if (lstate == L_BUSY && !first_cycle_in_busy && dmem_ready && !load_success) begin
                // 跳过 stale 后捕获真实读数据
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
    // L_RELEASE 期间将 load 结果注入前递链，确保后续指令可获取
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
        end else if (lstate == L_RELEASE) begin
            // load 结果已捕获，推入 ALU 前递链供后续指令使用
            rd_reg2 <= rd_reg;              rd_data_reg2 <= rd_data_reg;
            rd_reg  <= rd_reg_load;         rd_data_reg  <= rd_data_load_saved;
        end else if (!load_enable && reg_write_en) begin
            rd_reg2 <= rd_reg;              rd_data_reg2 <= rd_data_reg;
            rd_reg  <= rd_in;               rd_data_reg  <= rd_ex_result_in;
        end else begin
            // load 或非写寄存器指令：保持前递状态不变
            rd_reg2 <= rd_reg2;             rd_data_reg2 <= rd_data_reg2;
            rd_reg  <= rd_reg;              rd_data_reg  <= rd_data_reg;
        end
    end

    // 跳过 load 进入 EX/MEM 首个周期的 stale dmem_ready，
    // 等 data_mem 下周期返回真正的读数据。
    reg load_skip_stale;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush)
            load_skip_stale <= 1'b0;
        else if (lstate == L_BUSY && load_success && first_cycle_in_busy && dmem_ready_d1)
            load_skip_stale <= 1'b1;
        else
            load_skip_stale <= 1'b0;
    end

    // mem_busy_out 寄存器输出，消除竞争
    wire [1:0] lstate_next =
        (lstate == L_IDLE && load_enable)            ? L_BUSY :
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
        else            mem_busy_out_reg <= (lstate_next == L_BUSY) || slock_next || load_skip_stale;
    end

    assign rd_out      = rd_reg;
    assign rd_data_out = rd_data_reg;
    assign rd_out2      = rd_reg2;
    assign rd_data_out2 = rd_data_reg2;
    // load 在 EX 的第一个周期（load_enable=1, lstate 仍为 IDLE）就提前暴露 rd，
    // 使得 hazard_ctrl 能在依赖指令仍在 ID 阶段时检测到 load-use 冒险。
    assign rd_reg_load_out = (lstate == L_IDLE && load_enable) ? rd_in : rd_reg_load;
    assign rd_data_load_out = (lstate == L_RELEASE) ? rd_data_load_saved :
                              ((lstate == L_BUSY && dmem_ready && !first_cycle_in_busy) ? rd_mem_rdata_in :
                               rd_data_reg_load);
    assign load_lock_out = (lstate == L_BUSY) || (lstate == L_RELEASE);
    assign store_lock_out = slock;
    assign load_pending_out = (lstate == L_BUSY) || (lstate == L_IDLE && load_enable);
    // slock/L_BUSY 仅阻塞 store；load 的冲突由 hazard_ctrl 中 dmem_valid & ~dmem_ready 处理
    assign mem_stall_req = ((lstate == L_BUSY) || slock) && store_enable;
    assign load_skip_stale_out = load_skip_stale;
    assign mem_busy_out = mem_busy_out_reg;
endmodule
