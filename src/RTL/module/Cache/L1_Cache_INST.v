`timescale 1ns / 1ps
`include "../../include/soc_config.vh"
`include "./LFSR16_inst.v"
//
//采用组相连方式,写回方式为回写法，替换算法为组内随机替换
//
// 边界：CPU 侧与 core_top / IF 的 imem_* 握手一致；下层与 inst_mem 类接口 mem_* 一致。
//
module L1_Cache_INST #(
    parameter GROUP_NUM_WIDTH = `CACHE_BLOCK_NUMBER,//组数（位宽）
    parameter WAY_NUM_WIDTH = `CACHE_BLOCK_WAY_NUMBER,//每组路数（相联度）（位宽）
    parameter BLOCK_WIDTH = `CACHE_BLOCK_BYTE_SIZE_WIDTH,//块位宽(以字节为单位)
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

    (* ram_style = "block" *) reg [MEM_ADDR_WIDTH:0] Cache_addr [0:GROUP_NUM_WIDTH - 1][0:WAY_NUM_WIDTH - 1];//只存连续地址的首个32位地址,首位为有效位，相比存放4个32位地址，节省了4倍空间
    (* ram_style = "block" *) reg [1 << BLOCK_WIDTH << 3:0] Cache_inst [0:GROUP_NUM_WIDTH - 1][0:WAY_NUM_WIDTH - 1];//存inst_in，仍然存放4个32位的指令
    
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
    reg [((1 << BLOCK_WIDTH) << 3)-1:0] refill_line_buf;
    reg [((1 << BLOCK_WIDTH) << 3)-1:0] refill_line_next;
    
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
            for (ri = 0; ri < 1 << (GROUP_NUM_WIDTH - 1); ri = ri + 1) begin
                for (rj = 0; rj < 1 << (WAY_NUM_WIDTH - 1); rj = rj + 1) begin
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
            refill_line_buf <= {((1 << BLOCK_WIDTH) << 3){1'b0}};
        end else begin
            // 同拍命中判定（阻塞赋值，供本拍后续使用；等价于原 always@* 段）
            hit_found = 1'b0;
            hit_inst = inst_out;
            done = 1'b0;
            if (imem_req) begin
                for (hj = 0; hj < (1 << WAY_NUM_WIDTH) && !done; hj = hj + 1) begin
                    if (Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH] == 1'b1 &&
                        Cache_addr[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH-1:BLOCK_WIDTH] == imem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH]) begin
                        case (imem_addr[BLOCK_WIDTH - 1:0])
                            0: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][31:0];
                            1: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][63:32];
                            2: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][95:64];
                            3: hit_inst = Cache_inst[imem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][127:96];
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
                        refill_line_buf <= {((1 << BLOCK_WIDTH) << 3){1'b0}};
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
                        refill_line_buf <= {((1 << BLOCK_WIDTH) << 3){1'b0}};
                    end
                end
            end
        end
    end

endmodule
