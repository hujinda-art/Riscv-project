`timescale 1ns / 1ps
`include "../../include/soc_config.vh"
`include "./LFSR16_inst.v"
//
//采用组相连方式,写回方式为回写法，替换算法为组内随机替换
//
// 边界：CPU 侧与 core_top / IF 的 imem_* 握手一致；下层与 inst_mem 类接口 mem_* 一致。
//
module L1_Cache_INST #(
    // CACHE_BLOCK_NUMBER / CACHE_BLOCK_WAY_NUMBER：组索引、路选择所占**位数**
    // 组数 = 2^GROUP_NUM_WIDTH，路数 = 2^WAY_NUM_WIDTH，须与地址划分及阵列一致
    parameter GROUP_NUM_WIDTH = `CACHE_BLOCK_NUMBER,
    parameter WAY_NUM_WIDTH = `CACHE_BLOCK_WAY_NUMBER,
    parameter BLOCK_WIDTH = `CACHE_BLOCK_BYTE_SIZE_WIDTH,// log2(块字节数)，块大小 = 2^BLOCK_WIDTH 字节
    parameter INST_SIZE_WIDTH = `INSTR_SIZE,//指令大小（位宽）
    parameter MEM_ADDR_WIDTH = `MEM_ADDR_WIDTH//地址大小
)(
    input wire clk,
    input wire rst_n,
    // ---- CPU / 取指侧（与 core_top 的 imem_* 对接）----
    input wire [MEM_ADDR_WIDTH-1:0] imem_addr,
    input wire imem_req,
    output wire [INST_SIZE_WIDTH-1:0] imem_rdata,
    output wire imem_ready,
    // ---- 下层存储 / refill 侧（与 inst_mem 的 req/addr/inst/ready 对接）----
    output wire [MEM_ADDR_WIDTH-1:0] mem_addr,
    output wire mem_req,
    input wire [INST_SIZE_WIDTH-1:0] mem_rdata,
    input wire mem_ready
);

    // 与原端口等价的内部线网
    reg [INST_SIZE_WIDTH-1:0] inst_out;//输出到CPU的指令数据（内部寄存后再驱动 imem_rdata）
    reg imem_ready_reg;
    reg mem_req_reg;
    assign imem_rdata = inst_out;
    assign imem_ready = imem_ready_reg;
    assign mem_req = mem_req_reg;

    localparam NUM_SETS = 1 << GROUP_NUM_WIDTH;
    localparam NUM_WAYS = 1 << WAY_NUM_WIDTH;
    // 一行数据严格 128 位（勿用 [128:0] 共 129 位，易与字切片错位）
    localparam LINE_BITS = (1 << BLOCK_WIDTH) * 8;

    (* ram_style = "block" *) reg [MEM_ADDR_WIDTH:0] Cache_addr [0:NUM_SETS - 1][0:NUM_WAYS - 1];// 有效位+tag；tag 与 imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH] 比
    (* ram_style = "block" *) reg [LINE_BITS-1:0] Cache_inst [0:NUM_SETS - 1][0:NUM_WAYS - 1];// 一行 4×32bit 指令
    
    reg [MEM_ADDR_WIDTH-1:0] addr_reg;//地址寄存器（miss 时下层读地址）
    wire [15:0] lfsr_state;//LFSR 状态（与 lfsr16.state 位宽一致）
    reg done;//完成标志
    reg miss_pending;//miss等待内存返回
    reg hit_found;
    reg [INST_SIZE_WIDTH-1:0] hit_inst;
    wire [WAY_NUM_WIDTH-1:0] victim_way;
    reg [GROUP_NUM_WIDTH-1:0] refill_group_index;
    reg [BLOCK_WIDTH-1:2] refill_group_in_index;
    reg [WAY_NUM_WIDTH-1:0] refill_way;
    reg [MEM_ADDR_WIDTH-1:0] refill_base_addr;
    reg [1:0] refill_word_idx;
    reg [LINE_BITS-1:0] refill_line_buf;
    reg [LINE_BITS-1:0] refill_line_next;
    
    integer ri;
    integer rj;
    integer hj;

    lfsr16_inst u_lfsr16_inst(
        .clk(clk),
        .rst_n(rst_n),
        .advance(imem_req),
        .state(lfsr_state)
    );

    assign victim_way = lfsr_state[WAY_NUM_WIDTH - 1:0];
    assign mem_addr = miss_pending ? (refill_base_addr + {28'b0, refill_word_idx, 2'b00}) : addr_reg;
    //
    //时序逻辑：命中直返；miss向内存请求，返回后回填再返回给CPU
    //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin   //复位时，只清零有效位，其它位保持不变
            for (ri = 0; ri < NUM_SETS; ri = ri + 1) begin
                for (rj = 0; rj < NUM_WAYS; rj = rj + 1) begin
                    Cache_addr[ri][rj][MEM_ADDR_WIDTH] <= 1'b0;
                    
                end
            end
            inst_out <= {INST_SIZE_WIDTH{1'b0}};
            imem_ready_reg <= 1'b0;
            mem_req_reg <= 1'b0;
            miss_pending <= 1'b0;
            refill_group_index <= {GROUP_NUM_WIDTH{1'b0}};
            refill_group_in_index <= {(BLOCK_WIDTH-1){1'b0}};
            refill_way <= {WAY_NUM_WIDTH{1'b0}};
            refill_base_addr <= {MEM_ADDR_WIDTH{1'b0}};
            refill_word_idx <= 2'b00;
            refill_line_buf <= {LINE_BITS{1'b0}};
        end else begin
            // 同拍命中判定（阻塞赋值，供本拍后续使用；等价于原 always@* 段）
            hit_found = 1'b0;
            hit_inst = inst_out;
            done = 1'b0;
            if (imem_req) begin
                for (hj = 0; hj < NUM_WAYS && !done; hj = hj + 1) begin
                    if (Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH] == 1'b1 &&
                        Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH-1:BLOCK_WIDTH] == imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH]) begin
                        // 行内字索引为 addr[BLOCK_WIDTH-1:2]，勿用字节偏移 [BLOCK_WIDTH-1:0]
                        case (imem_addr[BLOCK_WIDTH - 1:2])
                            2'd0: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][31:0];
                            2'd1: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][63:32];
                            2'd2: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][95:64];
                            2'd3: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][127:96];
                            default: hit_inst = {INST_SIZE_WIDTH{1'b0}};
                        endcase
                        hit_found = 1'b1;
                        done = 1'b1;
                    end
                end
            end

            imem_ready_reg <= 1'b0;

            if (miss_pending) begin
                mem_req_reg <= 1'b1;
                if (mem_ready) begin
                    // 先在本地缓冲里累积整行，再一次性替换 cache line
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
                        mem_req_reg <= 1'b0;
                        miss_pending <= 1'b0;
                        refill_word_idx <= 2'b00;
                        refill_line_buf <= {LINE_BITS{1'b0}};
                        // 按需求：本拍不返回 CPU；下一拍重新按命中路径查找并返回
                    end else begin
                        refill_word_idx <= refill_word_idx + 2'd1;
                        refill_line_buf <= refill_line_next;
                    end
                end
            end else begin
                mem_req_reg <= 1'b0;
                if (imem_req) begin
                    addr_reg <= imem_addr;
                    if (hit_found) begin
                        inst_out <= hit_inst;
                        imem_ready_reg <= 1'b1;
                    end else begin
                        miss_pending <= 1'b1;
                        mem_req_reg <= 1'b1;
                        refill_group_index <= imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH];
                        refill_group_in_index <= imem_addr[BLOCK_WIDTH - 1:2];
                        refill_way <= victim_way;
                        refill_base_addr <= {imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH], {BLOCK_WIDTH{1'b0}}};
                        refill_word_idx <= 2'b00;
                        refill_line_buf <= {LINE_BITS{1'b0}};
                    end
                end
            end
        end
    end

endmodule
