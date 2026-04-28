`timescale 1ns / 1ps
`include "soc_top.v"

// FPGA implementation top-level.
// Only clk / rst_n / led are mapped to package pins.
// All internal debug buses stay on-chip.
//
// led[7:0] = ex_result_out[7:0]  (gives the optimizer an observable output
//            so it cannot remove the entire CPU as dead logic).
module fpga_top (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led          // connect to on-board LEDs in constraints
);
    wire [31:0] id_pc_w;
    wire [31:0] id_pc_plus4_w;
    wire [31:0] instr_out_w;
    wire        instr_valid_out_w;
    wire [6:0]  fun7_out_w;
    wire [4:0]  rs2_out_w;
    wire [4:0]  rs1_out_w;
    wire [2:0]  fuc3_out_w;
    wire [6:0]  opcode_out_w;
    wire [4:0]  rd_out_w;
    wire [31:0] ex_pc_out_w;
    wire [31:0] ex_pc_plus4_out_w;
    wire [31:0] ex_instr_out_w;
    wire        ex_instr_valid_out_w;
    wire [31:0] ex_imm_out_w;
    wire [31:0] ex_result_out_w;
    wire [31:0] ex_mem_addr_out_w;
    wire [31:0] ex_mem_wdata_out_w;

    // dont_touch prevents opt_design from removing the CPU as dead logic
    (* dont_touch = "yes" *)
    soc_top u_soc_top (
        .clk               (clk),
        .rst_n             (rst_n),
        .stall             (1'b0),
        .flush             (1'b0),
        .exception         (1'b0),
        .pc_exception      (32'b0),
        .interrupt         (1'b0),
        .pc_interrupt      (32'b0),
        .id_pc             (id_pc_w),
        .id_pc_plus4       (id_pc_plus4_w),
        .instr_out         (instr_out_w),
        .instr_valid_out   (instr_valid_out_w),
        .fun7_out          (fun7_out_w),
        .rs2_out           (rs2_out_w),
        .rs1_out           (rs1_out_w),
        .fuc3_out          (fuc3_out_w),
        .opcode_out        (opcode_out_w),
        .rd_out            (rd_out_w),
        .ex_pc_out         (ex_pc_out_w),
        .ex_pc_plus4_out   (ex_pc_plus4_out_w),
        .ex_instr_out      (ex_instr_out_w),
        .ex_instr_valid_out(ex_instr_valid_out_w),
        .ex_imm_out        (ex_imm_out_w),
        .ex_result_out     (ex_result_out_w),
        .ex_mem_addr_out   (ex_mem_addr_out_w),
        .ex_mem_wdata_out  (ex_mem_wdata_out_w)
    );

    // Drive LEDs from ex_result so the optimizer cannot prune the CPU.
    assign led = ex_result_out_w[7:0];

endmodule
