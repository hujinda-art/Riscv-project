`timescale 1ns / 1ps
`include "../include/soc_config.vh"
`include "IF.v"
`include "IF_ID_reg.v"
`include "ID.v"
`include "ID_EX_reg.v"
`include "EX.v"
`include "EX_MEM_reg.v"
`include "EX_WB_reg.v"
`include "MEM_WB_reg.v"
`include "WB_stage.v"
`include "../module/hazard_ctrl.v"
`include "../module/register_EX.v"
`include "../module/register_MEM.v"
`include "../module/register.v"
`include "medium_reg.v"

module core_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        stall,
    input  wire        flush,
    input  wire        exception,
    input  wire [31:0] pc_exception,
    input  wire        interrupt,
    input  wire [31:0] pc_interrupt,

   

    output wire [31:0] id_pc,
    output wire [31:0] id_pc_plus4,
    output wire [31:0] instr_out,
    output wire        instr_valid_out,

    output wire [6:0]  fun7_out,
    output wire [4:0]  rs2_out,
    output wire [4:0]  rs1_out,
    output wire [2:0]  fuc3_out,
    output wire [6:0]  opcode_out,
    output wire [4:0]  rd_out,

    output wire [31:0] ex_pc_out,
    output wire [31:0] ex_pc_plus4_out,
    output wire [31:0] ex_instr_out,
    output wire        ex_instr_valid_out,
    output wire [31:0] ex_imm_out,

    output wire [31:0] ex_result_out,
    output wire [31:0] ex_mem_addr_out,
    output wire [31:0] ex_mem_wdata_out,

    // 指令存储器总线（由 soc_top 连接实际存储器）
    output wire [31:0] imem_addr,
    output wire        imem_req,    // 取指请求
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready, // 指令总线就绪

    // 数据存储器总线（由 soc_top 连接实际存储器）
    output wire        dmem_wen,
    output wire        dmem_ren,    // 读使能
    output wire        dmem_valid,  // 访存请求有效
    output wire [1:0]  dmem_size,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready   // 数据总线就绪（load/store 统一）
);

    wire [31:0] if_pc_w;
    wire [31:0] if_pc_plus4_w;
    wire [31:0] if_instr;
    wire        if_instr_valid;

    wire        jump_if;
    wire [31:0] pc_jump_if;
    wire        jump_ifid_unused;
    wire [31:0] pc_jump_ifid_unused;
    wire [31:0] instr_to_id;

    wire [6:0]  id_fun7;
    wire [4:0]  id_rs2, id_rs1, id_rd;
    wire [2:0]  id_fuc3;
    wire [6:0]  id_opcode;
    wire [31:0] id_imm;
    wire        id_use_rs1, id_use_rs2, id_is_branch, id_is_jump;
    wire        id_is_jalr, id_is_load, id_is_store, id_reg_we;

    wire        ex_reg_write_en;
    wire        ex_use_rs1, ex_use_rs2, ex_is_branch;
    wire        ex_is_jalr, ex_is_load, ex_is_store;

    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    // WB 阶段：打包为寄存器堆写口（先声明，供寄存器堆实例使用）
    wire        wb_we_out;
    wire [4:0]  wb_waddr_out;
    wire [31:0] wb_wdata_out;

    wire        ex_branch_taken;
    wire [31:0] ex_pc_branch;
    wire        ex_jalr;
    wire [31:0] ex_pc_jalr;
    wire        ex_mem_ren;
    wire        ex_mem_wen;
    wire        exmem_mem_read_en_out;

    // ---------------------------
    // 内部 stall/flush 逻辑
    // ---------------------------
    wire load_use_hazard;
    wire branch_hazard_ex;
    wire branch_hazard_if;

    wire mem_stall;
    wire if_stall;
    wire stall_front;
    wire stall_back;
    wire stall_idex;
    assign stall_idex = stall_back;
    wire flush_ifid;
    wire flush_idex;
    hazard_ctrl u_hazard_ctrl (
        .stall(stall),
        .flush(flush),
        .jump_if(jump_if),
        .ex_branch_taken(ex_branch_taken),
        .ex_jalr(ex_jalr),
        .ex_instr_valid_out(ex_instr_valid_out),
        .rd_load_use(rd_reg_load_out),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_use_rs1(id_use_rs1),
        .id_use_rs2(id_use_rs2),
        .load_lock_in(load_lock_out),
        .load_pending_in(load_pending),
        .mem_stall_req(register_EX_mem_stall_req),
        .dmem_ready(dmem_ready),
        .imem_ready(imem_ready),
        .load_use_hazard(load_use_hazard),
        .branch_hazard_ex(branch_hazard_ex),
        .branch_hazard_if(branch_hazard_if),
        .mem_stall(mem_stall),
        .if_stall(if_stall),
        .stall_front(stall_front),
        .stall_back(stall_back),
        .flush_ifid(flush_ifid),
        .flush_idex(flush_idex)
    );

    // ID 阶段 JAL 决策：由 ID_stage 输出 is_jump 与 imm_j（经 imm_out）。
    localparam [6:0] OPCODE_JAL = 7'b1101111;
    assign jump_if    = id_is_jump && instr_valid_out;
    assign pc_jump_if = id_pc + id_imm;

    // JAL 链接写回（写口2）：rd <- PC+4
    wire jal_link_we = jump_if && (id_rd != 5'b0);

    // BRAM 寄存器堆的读操作是 registered（posedge 采样 raddr，下一拍输出 rdata）。
    // 读地址必须来自 ID 阶段（id_rs1/id_rs2），这样 posedge（ID→EX 转换）时
    // 采样的是即将进入 EX 的指令的源寄存器，rdata 在 EX 期间立即可用。
    // 若用 EX 阶段地址（rs1_out/rs2_out），rdata 会晚一拍，
    // 导致"2 条指令前"的结果无法通过寄存器堆旁路获取。
    reg_file_bram u_regfile (
        .clk(clk),
        .we(wb_we_out),
        .waddr(wb_waddr_out),
        .wdata(wb_wdata_out),
        .we2(jal_link_we),
        .waddr2(id_rd),
        .wdata2(id_pc_plus4),
        .raddr1(id_rs1),
        .rdata1(rf_rdata1),
        .raddr2(id_rs2),
        .rdata2(rf_rdata2)
    );

    wire [4:0] forward_rd_out;
    wire [31:0] forward_rd_data_out;
    wire [4:0] forward_rd_out2;
    wire [31:0] forward_rd_data_out2;
    wire [4:0] rd_reg_load_out;
    wire [31:0] rd_data_load_out;
    wire load_lock_out;
    wire store_lock_out;
    wire load_pending;
    wire register_EX_mem_stall_req;
    wire mem_stall_req;
    assign mem_stall_req = register_EX_mem_stall_req;
    wire register_EX_mem_busy;
    register_EX u_register_ex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_front),
        .flush(flush | branch_hazard_ex),
        .load_enable(ex_is_load),
        .store_enable(ex_is_store),
        .load_success(dmem_ready & exmem_mem_read_en_out),
        .dmem_ready(dmem_ready),
        .rd_in(rd_out),
        .rd_ex_result_in(ex_result_out),
        .rd_mem_rdata_in(dmem_rdata),
        .reg_write_en(ex_reg_write_en),
        .rd_out(forward_rd_out),
        .rd_data_out(forward_rd_data_out),
        .rd_out2(forward_rd_out2),
        .rd_data_out2(forward_rd_data_out2),
        .rd_reg_load_out(rd_reg_load_out),
        .rd_data_load_out(rd_data_load_out),
        .load_lock_out(load_lock_out),
        .store_lock_out(store_lock_out),
        .load_pending_out(load_pending),
        .mem_stall_req(register_EX_mem_stall_req),
        .mem_busy_out(register_EX_mem_busy)
    );

    IF_stage u_if (
        .clk(clk),
        .rst_n(rst_n),
        .stall_pc(stall_front),
        .flush(flush_ifid),
        .exception(exception),
        .pc_exception(pc_exception),
        .interrupt(interrupt),
        .pc_interrupt(pc_interrupt),
        .jalr(ex_jalr),
        .pc_jalr(ex_pc_jalr),
        .jump(jump_if),
        .pc_jump(pc_jump_if),
        .branch(ex_branch_taken),
        .pc_branch(ex_pc_branch),
        .if_pc(if_pc_w),
        .if_pc_plus4(if_pc_plus4_w),
        .imem_addr(imem_addr),
        .imem_req(imem_req),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .instr_out(if_instr),
        .instr_valid_out(if_instr_valid)
    );

    IF_ID_reg u_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_front),
        .flush(flush_ifid),
        .if_pc(if_pc_w),
        .if_pc_plus4(if_pc_plus4_w),
        .instr_in(if_instr),
        .instr_valid_in(if_instr_valid),
        .id_pc(id_pc),
        .id_pc_plus4(id_pc_plus4),
        .instr_out(instr_out),
        .instr_valid_out(instr_valid_out)
    );

    ID_stage u_id (
        .instr_in(instr_out),
        .fun7(id_fun7),
        .rs2(id_rs2),
        .rs1(id_rs1),
        .fuc3(id_fuc3),
        .opcode(id_opcode),
        .rd(id_rd),
        .imm_out(id_imm),
        .use_rs1(id_use_rs1),
        .use_rs2(id_use_rs2),
        .is_branch(id_is_branch),
        .is_jump(id_is_jump),
        .is_jalr(id_is_jalr),
        .is_load(id_is_load),
        .is_store(id_is_store),
        .reg_write_en(id_reg_we)
    );

    ID_EX_reg u_id_ex (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_back),
        .flush(flush_idex),
        .id_pc_in(id_pc),
        .id_pc_plus4_in(id_pc_plus4),
        // JAL 气泡由 hazard_ctrl 的 flush_idex（含 branch_hazard_if & ~stall_back）统一注入，
        // 避免 jump_if 与 stall_back 不同步时误把 hold 中的 store 清成 NOP。
        .instr_in(instr_out),
        .instr_valid_in(instr_valid_out),
        .fun7_in(id_fun7),
        .rs1_in(id_rs1),
        .rs2_in(id_rs2),
        .fuc3_in(id_fuc3),
        .opcode_in(id_opcode),
        .rd_in(id_rd),
        .imm_in(id_imm),
        .reg_write_en_in(id_reg_we),
        .use_rs1_in(id_use_rs1),
        .use_rs2_in(id_use_rs2),
        .is_branch_in(id_is_branch),
        .is_jalr_in(id_is_jalr),
        .is_load_in(id_is_load),
        .is_store_in(id_is_store),
        .ex_pc(ex_pc_out),
        .ex_pc_plus4(ex_pc_plus4_out),
        .ex_instr(ex_instr_out),
        .ex_instr_valid(ex_instr_valid_out),
        .ex_fun7(fun7_out),
        .ex_rs1(rs1_out),
        .ex_rs2(rs2_out),
        .ex_fuc3(fuc3_out),
        .ex_opcode(opcode_out),
        .ex_rd(rd_out),
        .ex_imm(ex_imm_out),
        .ex_reg_write_en(ex_reg_write_en),
        .ex_use_rs1(ex_use_rs1),
        .ex_use_rs2(ex_use_rs2),
        .ex_is_branch(ex_is_branch),
        .ex_is_jalr(ex_is_jalr),
        .ex_is_load(ex_is_load),
        .ex_is_store(ex_is_store)
    );

    EX_stage u_ex (
        .ex_instr_valid(ex_instr_valid_out),
        .ex_pc(ex_pc_out),
        .ex_pc_plus4(ex_pc_plus4_out),
        .ex_fun7(fun7_out),
        .ex_rs1(rs1_out),
        .ex_rs2(rs2_out),
        .ex_fuc3(fuc3_out),
        .ex_opcode(opcode_out),
        .ex_imm(ex_imm_out),
        .ex_is_branch(ex_is_branch),
        .ex_is_jalr(ex_is_jalr),
        .ex_is_load(ex_is_load),
        .ex_is_store(ex_is_store),
        .rs1_data(rf_rdata1),
        .rs2_data(rf_rdata2),
        .forward_rd_in(forward_rd_out),
        .forward_rd_data_in(forward_rd_data_out),
        .forward_load_lock_in(load_lock_out),
        .forward_store_lock_in(store_lock_out),
        .forward_rd_reg_load_in(rd_reg_load_out),
        .forward_rd_data_reg_load_in(rd_data_load_out),
        .ex_result(ex_result_out),
        .mem_addr_out(ex_mem_addr_out),
        .mem_wdata(ex_mem_wdata_out),
        .mem_read_en(ex_mem_ren),
        .mem_write_en(ex_mem_wen),
        .branch_taken(ex_branch_taken),
        .pc_branch(ex_pc_branch),
        .jalr(ex_jalr),
        .pc_jalr(ex_pc_jalr)
    );

    wire [31:0] wb_result_out;
    wire [4:0]  wb_rd_out_ex;
    wire        wb_reg_write_en_out;
    EX_WB_reg u_ex_wb (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_back),
        .flush(flush),
        .ex_result(ex_result_out),
        .ex_rd(rd_out),
        .ex_reg_write_en(ex_reg_write_en),
        .load_occupation(1'b0),
        .wb_result(wb_result_out),
        .wb_rd(wb_rd_out_ex),
        .wb_reg_write_en(wb_reg_write_en_out)
    );

    // ---------------------------
    // EX/MEM + MEM/WB + 写回（先实现 WB 路径；load 的 MEM 结果后续接上）
    // ---------------------------
    wire        exmem_mem_write_en_out;
    wire        exmem_reg_write_en_out;
    wire [4:0]  exmem_rd_out;
    wire [31:0] exmem_mem_addr_out;
    wire [31:0] exmem_mem_wdata_out;

    EX_MEM_reg u_exmem (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_back),
        .flush(flush),
        .ex_mem_read_en_in(ex_mem_ren),
        .ex_mem_write_en_in(ex_mem_wen),
        .ex_reg_write_en_in(ex_reg_write_en),
        .ex_rd_in(rd_out),
        .ex_mem_addr_in(ex_mem_addr_out),
        .ex_mem_wdata_in(ex_mem_wdata_out),
        .mem_mem_read_en_out(exmem_mem_read_en_out),
        .mem_mem_write_en_out(exmem_mem_write_en_out),
        .mem_reg_write_en_out(exmem_reg_write_en_out),
        .mem_rd_out(exmem_rd_out),
        .mem_mem_addr_out(exmem_mem_addr_out),
        .mem_mem_wdata_out(exmem_mem_wdata_out)
    );

    // 数据总线信号直接从 EX/MEM 寄存器输出驱动，由 soc_top 连接到实际存储器
    wire [1:0] mem_size_fixed = `SOC_MEM_SIZE_WORD; // 与 soc_config.vh 一致
    assign dmem_wen   = exmem_mem_write_en_out;
    assign dmem_ren   = exmem_mem_read_en_out;
    assign dmem_valid = exmem_mem_write_en_out | exmem_mem_read_en_out;
    assign dmem_size  = mem_size_fixed;
    assign dmem_addr  = exmem_mem_addr_out;
    assign dmem_wdata = exmem_mem_wdata_out;

    // 访存数据由 soc_top 直连返回；MEM_stage 占位模块可省略。
    wire [31:0] mem_load_data_stub = exmem_mem_read_en_out ? dmem_rdata : 32'b0;

    wire        wb_is_load_out;
    wire [4:0]  wb_rd_out_mem;
    wire [31:0] wb_load_data_out;

    MEM_WB_reg u_memwb (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_back),
        .flush(flush),
        .mem_is_load_in(exmem_mem_read_en_out),
        .mem_rd_in(exmem_rd_out),
        .mem_load_data_in(mem_load_data_stub),
        .wb_is_load_out(wb_is_load_out),
        .wb_rd_out(wb_rd_out_mem),
        .wb_load_data_out(wb_load_data_out)
    );

    WB_stage u_wb (
        .wb_reg_write_en_in(wb_reg_write_en_out),
        .wb_is_load_in(wb_is_load_out),
        .wb_rd_in_ex(wb_rd_out_ex),
        .wb_rd_in_mem(wb_rd_out_mem),
        .wb_alu_result_in(wb_result_out),
        .wb_load_data_in(wb_load_data_out),
        .wb_we_out(wb_we_out),
        .wb_waddr_out(wb_waddr_out),
        .wb_wdata_out(wb_wdata_out)
    );

endmodule
