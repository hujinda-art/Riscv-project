`timescale 1ns / 1ps
//
// Minimal core testbench
// - Loads instructions from program.hex (inst_mem reads "program.hex")
// - Runs for a fixed number of cycles
// - Dumps a few registers to check WB + JAL link behavior
//
module tb_core;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    // Core control inputs
    reg        stall      = 1'b0;
    reg        flush      = 1'b0;
    reg        exception  = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg        interrupt  = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

    // DUT outputs (unused here, but keep ports driven)
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] instr_out;
    wire        instr_valid_out;

    wire [6:0]  fun7_out;
    wire [4:0]  rs2_out;
    wire [4:0]  rs1_out;
    wire [2:0]  fuc3_out;
    wire [6:0]  opcode_out;
    wire [4:0]  rd_out;

    wire [31:0] ex_pc_out;
    wire [31:0] ex_pc_plus4_out;
    wire [31:0] ex_instr_out;
    wire        ex_instr_valid_out;
    wire [31:0] ex_imm_out;
    wire [31:0] ex_result_out;
    wire [31:0] ex_mem_addr_out;
    wire [31:0] ex_mem_wdata_out;

    core_top dut (
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

    always #5 clk = ~clk;

    initial begin
        // Reset
        #25;
        rst_n = 1'b1;

        // Run enough cycles for IF/ID/ID_EX/EX_MEM/MEM_WB to propagate.
        repeat (40) @(posedge clk);

        // regs[] is inside reg_file_bram instance u_regfile
        $display("x1=%h x2=%h x3=%h x4=%h x5=%h",
                 dut.u_regfile.regs[1],
                 dut.u_regfile.regs[2],
                 dut.u_regfile.regs[3],
                 dut.u_regfile.regs[4],
                 dut.u_regfile.regs[5]);

        $stop;
    end

endmodule

