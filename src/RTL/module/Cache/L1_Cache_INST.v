`timescale 1ns / 1ps
`include "../../include/soc_config.vh"
`include "./LFSR16_inst.v"
//
// 组相联 L1 指令 Cache（回写法、组内随机替换）
// CPU 侧与 core_top / IF 的 imem_* 握手一致；下层与 inst_mem 类接口 mem_* 一致。
//
// 关键改进：命中路径为组合逻辑，消除 inst_out 寄存器引入的一拍延迟。
// 这确保了 JAL 跳转至未缓存行时，IF 阶段能在 PC 改变当拍看到正确的 imem_ready。
//
module L1_Cache_INST #(
    parameter GROUP_NUM_WIDTH = `CACHE_BLOCK_NUMBER,
    parameter WAY_NUM_WIDTH   = `CACHE_BLOCK_WAY_NUMBER,
    parameter BLOCK_WIDTH     = `CACHE_BLOCK_BYTE_SIZE_WIDTH,
    parameter INST_SIZE_WIDTH = `INSTR_SIZE,
    parameter MEM_ADDR_WIDTH  = `MEM_ADDR_WIDTH
)(
    input  wire clk,
    input  wire rst_n,
    // ---- CPU / 取指侧 ----
    input  wire [MEM_ADDR_WIDTH-1:0] imem_addr,
    input  wire                      imem_req,
    output wire [INST_SIZE_WIDTH-1:0] imem_rdata,
    output wire                      imem_ready,
    // ---- 下层存储 / refill 侧 ----
    output wire [MEM_ADDR_WIDTH-1:0] mem_addr,
    output wire                      mem_req,
    input  wire [INST_SIZE_WIDTH-1:0] mem_rdata,
    input  wire                      mem_ready
);

    localparam NUM_SETS  = 1 << GROUP_NUM_WIDTH;
    localparam NUM_WAYS  = 1 << WAY_NUM_WIDTH;
    localparam LINE_BITS = (1 << BLOCK_WIDTH) * 8;

    (* ram_style = "block" *) reg [MEM_ADDR_WIDTH:0] Cache_addr [0:NUM_SETS - 1][0:NUM_WAYS - 1];
    (* ram_style = "block" *) reg [LINE_BITS-1:0]       Cache_inst [0:NUM_SETS - 1][0:NUM_WAYS - 1];

    // ---- 组合逻辑命中检测 ----
    reg        hit_found;
    reg [INST_SIZE_WIDTH-1:0] hit_data;
    integer    hj;

    always @(*) begin
        hit_found = 1'b0;
        hit_data  = {INST_SIZE_WIDTH{1'b0}};
        if (imem_req) begin
            for (hj = 0; hj < NUM_WAYS; hj = hj + 1) begin
                if (Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH] == 1'b1 &&
                    Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH-1:BLOCK_WIDTH] == imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH]) begin
                    case (imem_addr[BLOCK_WIDTH - 1:2])
                        2'd0: hit_data = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][31:0];
                        2'd1: hit_data = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][63:32];
                        2'd2: hit_data = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][95:64];
                        2'd3: hit_data = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][127:96];
                        default: hit_data = {INST_SIZE_WIDTH{1'b0}};
                    endcase
                    hit_found = 1'b1;
                end
            end
        end
    end

    // ---- 内部寄存器 ----
    reg [INST_SIZE_WIDTH-1:0] inst_out_reg;
    reg imem_ready_reg;
    reg mem_req_reg;
    reg miss_pending;

    reg [MEM_ADDR_WIDTH-1:0] addr_reg;
    reg [GROUP_NUM_WIDTH-1:0] refill_group_index;
    reg [WAY_NUM_WIDTH-1:0]   refill_way;
    reg [MEM_ADDR_WIDTH-1:0] refill_base_addr;
    reg [1:0]                 refill_word_idx;
    reg [LINE_BITS-1:0]       refill_line_buf;
    reg [LINE_BITS-1:0]       refill_line_next;

    wire [15:0] lfsr_state;
    wire [WAY_NUM_WIDTH-1:0] victim_way;
    assign victim_way = lfsr_state[WAY_NUM_WIDTH - 1:0];

    integer ri, rj;

    lfsr16_inst u_lfsr16_inst(
        .clk(clk), .rst_n(rst_n),
        .advance(imem_req),
        .state(lfsr_state)
    );

    // ---- 输出：命中时组合直通，miss 时使用寄存器路径 ----
    assign imem_rdata = hit_found ? hit_data : inst_out_reg;
    assign imem_ready = hit_found ? 1'b1 : imem_ready_reg;
    assign mem_req    = mem_req_reg;
    assign mem_addr   = miss_pending ? (refill_base_addr + {28'b0, refill_word_idx, 2'b00}) : addr_reg;

    // ---- 时序逻辑：miss 处理与 refill ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ri = 0; ri < NUM_SETS; ri = ri + 1) begin
                for (rj = 0; rj < NUM_WAYS; rj = rj + 1) begin
                    Cache_addr[ri][rj][MEM_ADDR_WIDTH] <= 1'b0;
                end
            end
            inst_out_reg   <= {INST_SIZE_WIDTH{1'b0}};
            imem_ready_reg <= 1'b0;
            mem_req_reg    <= 1'b0;
            miss_pending   <= 1'b0;
            refill_group_index <= {GROUP_NUM_WIDTH{1'b0}};
            refill_way     <= {WAY_NUM_WIDTH{1'b0}};
            refill_base_addr <= {MEM_ADDR_WIDTH{1'b0}};
            refill_word_idx  <= 2'b00;
            refill_line_buf  <= {LINE_BITS{1'b0}};
        end else begin
            imem_ready_reg <= 1'b0;

            if (miss_pending) begin
                mem_req_reg <= 1'b1;
                if (mem_ready) begin
                    refill_line_next = refill_line_buf;
                    case (refill_word_idx)
                        2'd0: refill_line_next[31:0]   = mem_rdata;
                        2'd1: refill_line_next[63:32]  = mem_rdata;
                        2'd2: refill_line_next[95:64]  = mem_rdata;
                        2'd3: refill_line_next[127:96] = mem_rdata;
                    endcase
                    if (refill_word_idx == 2'd3) begin
                        Cache_addr[refill_group_index][refill_way][MEM_ADDR_WIDTH] <= 1'b1;
                        Cache_addr[refill_group_index][refill_way][MEM_ADDR_WIDTH-1:0] <= {addr_reg[MEM_ADDR_WIDTH-1:BLOCK_WIDTH], {BLOCK_WIDTH{1'b0}}};
                        Cache_inst[refill_group_index][refill_way] <= refill_line_next;
                        mem_req_reg   <= 1'b0;
                        miss_pending  <= 1'b0;
                        refill_word_idx <= 2'b00;
                        refill_line_buf <= {LINE_BITS{1'b0}};
                    end else begin
                        refill_word_idx <= refill_word_idx + 2'd1;
                        refill_line_buf <= refill_line_next;
                    end
                end
            end else begin
                mem_req_reg <= 1'b0;
                if (imem_req) begin
                    addr_reg <= imem_addr;
                    if (!hit_found) begin
                        miss_pending <= 1'b1;
                        mem_req_reg  <= 1'b1;
                        refill_group_index <= imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH];
                        refill_way    <= victim_way;
                        refill_base_addr <= {imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH], {BLOCK_WIDTH{1'b0}}};
                        refill_word_idx <= 2'b00;
                        refill_line_buf <= {LINE_BITS{1'b0}};
                    end
                end
            end
        end
    end

endmodule
