`timescale 1ns / 1ps
module register_EX(
    input wire clk,
    input wire rst_n,
    input wire stall,
    input wire flush,
    input wire load_enable,
    input wire load_success,
    input wire [4:0] rd_in,
    input wire [31:0] rd_ex_result_in,
    input wire [31:0] rd_mem_rdata_in,
    output wire [4:0] rd_out,
    output wire [31:0] rd_data_out,
    output wire [4:0] rd_reg_load_out,
    output wire [31:0] rd_data_reg_load_out,
    output wire load_lock_out
);
    parameter   NOP_REG = 5'b00000;
    parameter   NOP_DATA = 32'h00000000;

    reg [4:0] rd_reg;
    reg [4:0] rd_reg_load;
    reg [31:0] rd_data_reg;
    reg [31:0] rd_data_reg_load;

    reg load_lock;

    // load_lock：LW 进入 EX 时置 1（数据未就绪），收到 load_success 时清 0（数据已就绪可前递）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_lock <= 1'b0;
        end else if (flush) begin
            load_lock <= 1'b0;
        end else if (load_success) begin
            load_lock <= 1'b0;
        end else if (load_enable) begin
            load_lock <= 1'b1;
        end else begin
            load_lock <= load_lock;
        end
    end

    // rd_reg_load / rd_data_reg_load：Load 前递专用通道。
    // load_enable 时锁存目的寄存器；load_success 时仅更新数据，目的寄存器保持不变。
    // 两个分支必须分开：load_success 时 rd_in 来自流水线中的 NOP（x0），
    // 若与 load_enable 合并写入 rd_in 会把 x0 覆盖真正的目的寄存器。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg_load <= NOP_REG;
            rd_data_reg_load <= NOP_DATA;
        end else if (flush) begin
            rd_reg_load <= NOP_REG;
            rd_data_reg_load <= NOP_DATA;
        end else if (load_success) begin
            rd_data_reg_load <= rd_mem_rdata_in;   // 只更新数据，保留目的寄存器
        end else if (load_enable) begin
            rd_reg_load  <= rd_in;                  // 锁存目的寄存器
            rd_data_reg_load <= rd_ex_result_in;    // 暂存（地址），等 load_success 替换
        end else begin
            rd_reg_load <= rd_reg_load;
            rd_data_reg_load <= rd_data_reg_load;
        end
    end

    // rd_reg / rd_data_reg：ALU 结果前递通道（非 Load 指令）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg <= 5'b0;
            rd_data_reg <= 32'b0;
        end else if (flush) begin
            rd_reg <= 5'b0;
            rd_data_reg <= 32'b0;
        end else if (stall) begin
            rd_reg <= rd_reg;
            rd_data_reg <= rd_data_reg;
        end else if (!load_enable) begin
            rd_reg <= rd_in;
            rd_data_reg <= rd_ex_result_in;    // 始终使用 EX 结果，与 load 数据路径无关
        end else begin
            rd_reg <= rd_reg;
            rd_data_reg <= rd_data_reg;
        end
    end

    assign rd_out = rd_reg;
    assign rd_data_out = rd_data_reg;
    assign rd_reg_load_out = rd_reg_load;
    assign rd_data_reg_load_out = rd_data_reg_load;
    assign load_lock_out = load_lock;
endmodule
