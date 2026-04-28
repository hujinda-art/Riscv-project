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
//-----------------------------------------------------------------------------
    input  wire        ex_branch_mispredict,
//-----------------------------------------------------------------------------
    input  wire        ex_branch_taken,
    input  wire        ex_jalr,
    input  wire        ex_instr_valid_out,
    input  wire        ex_is_load,
    input  wire [4:0]  rd_out,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_use_rs1,
    input  wire        id_use_rs2,
    input  wire        exmem_mem_read_en_out,
    input  wire        exmem_mem_write_en_out,
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

    assign load_use_hazard =
        (ex_instr_valid_out && ex_is_load && (rd_out != 5'b0) && (
            (id_use_rs1 && (id_rs1 == rd_out)) ||
            (id_use_rs2 && (id_rs2 == rd_out))
        ));
//-----------------------------------------------------------------------------
//删除assign branch_hazard_ex = ex_branch_mispredict | ex_jalr; --- IGNORE ---
    assign branch_hazard_ex = ex_branch_mispredict | ex_jalr;
//-----------------------------------------------------------------------------
    assign branch_hazard_if = jump_if;

    assign mem_stall  = (exmem_mem_read_en_out | exmem_mem_write_en_out) & ~dmem_ready;
    assign if_stall   = ~imem_ready;
    assign stall_front = stall | load_use_hazard | mem_stall | if_stall;
    assign stall_back  = stall | mem_stall;
    assign flush_ifid  = flush | branch_hazard_ex | branch_hazard_if;
    // JAL 在 ID 阶段已重定向 PC；需对 ID/EX 注入气泡，但不能在 mem_stall 时冲刷
    // （此时 ID_EX 可能正 hold 上一条访存指令，flush 优先于 stall 会误清有效 store）。
    assign flush_idex  = flush | branch_hazard_ex | load_use_hazard
                        | (branch_hazard_if & ~stall_back);

endmodule
