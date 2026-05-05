`timescale 1ns / 1ps
//
// Hazard control comb logic:
// - load-use detect
// - branch/jalr/jal hazard combine
// - front/back stall split
// - IF/ID and ID/EX flush split
//
module hazard_ctrl (
    input  wire        stall,
    input  wire        flush,
    input  wire        jump_if,
    input  wire        ex_branch_taken,
    input  wire        ex_jalr,
    input  wire        ex_instr_valid_out,
    input  wire [4:0]  rd_load_use,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_use_rs1,
    input  wire        id_use_rs2,
    input  wire        load_lock_in,
    input  wire        load_pending_in,
    input  wire        mem_stall_req,
    input  wire        load_skip_stale,
    input  wire        dmem_valid,
    input  wire        dmem_ready,
    input  wire        imem_ready,
    output wire        load_use_hazard,
    output wire        branch_hazard_ex,
    output wire        branch_hazard_if,
    output wire        mem_stall,
    output wire        if_stall,
    output wire        stall_front,
    output wire        stall_back,
    output wire        flush_ifid,
    output wire        flush_idex
);

    // load_use_hazard：当 load 处于 L_BUSY（数据尚未返回）且 ID 段指令存在 RAW
    // 依赖时停顿前端。L_RELEASE 期间数据已通过 rd_data_load_out 前递，无需停顿。
    assign load_use_hazard =
        (load_pending_in && (rd_load_use != 5'b0) && (
            (id_use_rs1 && (id_rs1 == rd_load_use)) ||
            (id_use_rs2 && (id_rs2 == rd_load_use))
        ));

    assign branch_hazard_ex = ex_branch_taken | ex_jalr;
    assign branch_hazard_if = jump_if;

    // mem_stall 三条件：(1) store 被锁阻塞 (2) EX/MEM 有未完成访存
    // (3) load 首周期 stale ready 被跳过，需等 data_mem 返回真实读数据
    assign mem_stall  = mem_stall_req | (dmem_valid & ~dmem_ready) | load_skip_stale;
    assign if_stall   = ~imem_ready;
    assign stall_front = stall | load_use_hazard | mem_stall | if_stall;
    assign stall_back  = stall | mem_stall;
    assign flush_ifid  = flush | branch_hazard_ex | branch_hazard_if;
    // load_use_hazard 仅在 stall_back=0（load 可前进到 EX/MEM）时才 flush ID_EX，
    // 否则 flush 会先于 stall 杀死仍卡在 EX 的 load 自身。
    assign flush_idex  = flush | branch_hazard_ex
                        | (load_use_hazard & ~stall_back)
                        | (branch_hazard_if & ~stall_back);

endmodule
