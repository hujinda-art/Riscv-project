`timescale 1ns / 1ps

module tb_core_jump;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg        stall = 1'b0;
    reg        flush = 1'b0;
    reg        exception = 1'b0;
    reg [31:0] pc_exception = 32'b0;
    reg        interrupt = 1'b0;
    reg [31:0] pc_interrupt = 32'b0;

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
        // 覆盖指令存储器内容，避免依赖外部 program.hex
        // 0x00: addi x2, x0, 1
        dut.u_if.u_inst_mem.mem[0] = 32'h00100113;
        // 0x04: jal x0, +8  (跳到 0x0C)
        dut.u_if.u_inst_mem.mem[1] = 32'h0080006F;
        // 0x08: addi x3, x0, 7  (应被跳过)
        dut.u_if.u_inst_mem.mem[2] = 32'h00700193;
        // 0x0C: addi x4, x0, 9  (应执行)
        dut.u_if.u_inst_mem.mem[3] = 32'h00900213;
        // 后续填充 NOP
        dut.u_if.u_inst_mem.mem[4] = 32'h00000013;
        dut.u_if.u_inst_mem.mem[5] = 32'h00000013;
        dut.u_if.u_inst_mem.mem[6] = 32'h00000013;
        dut.u_if.u_inst_mem.mem[7] = 32'h00000013;

        #20 rst_n = 1'b1;

        repeat (60) @(posedge clk);

        $display("x2=%0d x3=%0d x4=%0d",
                 dut.u_regfile.regs[2],
                 dut.u_regfile.regs[3],
                 dut.u_regfile.regs[4]);

        if (dut.u_regfile.regs[2] !== 32'd1) begin
            $display("FAIL: x2 should be 1");
        end
        if (dut.u_regfile.regs[3] !== 32'd0) begin
            $display("FAIL: x3 should remain 0 (instruction at 0x08 skipped)");
        end
        if (dut.u_regfile.regs[4] !== 32'd9) begin
            $display("FAIL: x4 should be 9 (jump target executed)");
        end

        $stop;
    end
endmodule

