`timescale 1ns / 1ps
//
// 访存冲突控制（从 register_EX 中解耦）：
// - 维护单 outstanding 访存状态（mem_inflight）
// - 在锁冲突或 outstanding 未完成时阻止新访存发起
// - 产生 mem_stall_req 给 hazard_ctrl，用于冻结 IF/ID、ID/EX
//
module mem_conflict_ctrl (
    input  wire clk,
    input  wire rst_n,
    input  wire flush,
    input  wire stall,
    input  wire ex_mem_req,          // EX 当前拍是否为访存请求（load/store）
    input  wire dmem_ready,          // 数据存储器响应
    input  wire ex_lock_conflict,    // EX 锁冲突（来自 register_EX 的 load/store lock）
    output wire mem_issue_allow,     // 本拍是否允许把访存推进到 EX/MEM
    output wire mem_stall_req,       // 给 hazard_ctrl 的 stall 请求
    output wire mem_inflight         // 调试/观测用
);
    reg inflight_reg;

    // 先后顺序：先处理 EX 锁冲突，再处理 outstanding 访存占用
    wire blocked_by_lock = ex_lock_conflict;
    wire blocked_by_busy = inflight_reg;
    assign mem_issue_allow = ~blocked_by_lock & ~blocked_by_busy;

    // 只要有 outstanding 未完成，或者本拍被锁冲突挡住，就持续请求 stall
    assign mem_stall_req = blocked_by_lock | blocked_by_busy;
    assign mem_inflight  = inflight_reg;

    wire issue_fire = ex_mem_req & mem_issue_allow;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inflight_reg <= 1'b0;
        end else if (flush) begin
            inflight_reg <= 1'b0;
        end else if (stall) begin
            inflight_reg <= inflight_reg;
        end else begin
            // dmem_ready 优先于新发起，避免同拍先清后置的歧义
            if (inflight_reg && dmem_ready) begin
                inflight_reg <= 1'b0;
            end else if (!inflight_reg && issue_fire) begin
                inflight_reg <= 1'b1;
            end
        end
    end
endmodule

