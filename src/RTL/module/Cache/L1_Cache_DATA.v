`timescale 1ns / 1ps
`include "../../include/soc_config.vh"
`include "./LFSR16_data.v"
//
// 组相联 L1 数据 Cache（写直达 + 写不分配）
// - 读命中：直接返回
// - 读未命中：向下层发起一次读，返回后回填并返回
// - 写命中：更新 cache 行对应字，同时向下层发写
// - 写未命中：仅向下层发写（不回填）
// - 替换：读 miss 回填时使用 lfsr16_data 随机选路
//
// 接口约束：
// - CPU 侧使用 core_top/soc_top 的 dmem_* 信号
// - 下层侧使用 data_mem 的 valid/read_en/write_en/size/address/data_in/data_out/ready
//
module L1_Cache_DATA #(
    parameter GROUP_NUM_WIDTH = `CACHE_BLOCK_NUMBER,
    parameter WAY_NUM_WIDTH   = `CACHE_BLOCK_WAY_NUMBER,
    parameter BLOCK_WIDTH     = `CACHE_BLOCK_BYTE_SIZE_WIDTH,
    parameter DATA_SIZE_WIDTH = `DATA_SIZE,
    parameter MEM_ADDR_WIDTH  = `MEM_ADDR_WIDTH
)(
    input  wire                      clk,
    input  wire                      rst_n,
    // ---- CPU 侧（对接 core_top 的 dmem_*）----
    input  wire                      dmem_valid,
    input  wire                      dmem_ren,
    input  wire                      dmem_wen,
    input  wire [1:0]                dmem_size,
    input  wire [MEM_ADDR_WIDTH-1:0] dmem_addr,
    input  wire [DATA_SIZE_WIDTH-1:0] dmem_wdata,
    output wire [DATA_SIZE_WIDTH-1:0] dmem_rdata,
    output wire                      dmem_ready,
    // ---- 下层存储侧（对接 data_mem）----
    output wire                      mem_valid,
    output wire                      mem_read_en,
    output wire                      mem_write_en,
    output wire [1:0]                mem_size,
    output wire [MEM_ADDR_WIDTH-1:0] mem_addr,
    output wire [DATA_SIZE_WIDTH-1:0] mem_wdata,
    input  wire [DATA_SIZE_WIDTH-1:0] mem_rdata,
    input  wire                      mem_ready
);

    // [valid|addr_base]，addr_base 低 BLOCK_WIDTH 位恒为 0
    (* ram_style = "block" *) reg [MEM_ADDR_WIDTH:0] Cache_addr [0:(1 << GROUP_NUM_WIDTH) - 1][0:(1 << WAY_NUM_WIDTH) - 1];
    // 每行为 16B（4 x 32b）
    (* ram_style = "block" *) reg [((1 << BLOCK_WIDTH) << 3)-1:0] Cache_data [0:(1 << GROUP_NUM_WIDTH) - 1][0:(1 << WAY_NUM_WIDTH) - 1];

    reg [DATA_SIZE_WIDTH-1:0] dmem_rdata_reg;
    reg dmem_ready_reg;
    assign dmem_rdata = dmem_rdata_reg;
    assign dmem_ready = dmem_ready_reg;

    // 下行总线控制
    reg mem_valid_reg;
    reg mem_read_en_reg;
    reg mem_write_en_reg;
    reg [1:0] mem_size_reg;
    reg [MEM_ADDR_WIDTH-1:0] mem_addr_reg;
    reg [DATA_SIZE_WIDTH-1:0] mem_wdata_reg;

    assign mem_valid    = mem_valid_reg;
    assign mem_read_en  = mem_read_en_reg;
    assign mem_write_en = mem_write_en_reg;
    assign mem_size     = mem_size_reg;
    assign mem_addr     = mem_addr_reg;
    assign mem_wdata    = mem_wdata_reg;

    // miss/访存等待状态
    reg pending_read_miss;
    reg pending_write_through;

    // 保留当前正在处理的请求
    reg [MEM_ADDR_WIDTH-1:0] req_addr_reg;
    reg [DATA_SIZE_WIDTH-1:0] req_wdata_reg;
    reg [1:0] req_size_reg;
    reg req_is_read_reg;

    // 读 miss 回填位置信息
    reg [GROUP_NUM_WIDTH-1:0] refill_group_index;
    reg [BLOCK_WIDTH-1:0] refill_word_offset;
    reg [WAY_NUM_WIDTH-1:0] refill_way;

    // 命中组合结果（在时序块内阻塞赋值）
    reg hit_found;
    reg [WAY_NUM_WIDTH-1:0] hit_way;
    reg [DATA_SIZE_WIDTH-1:0] hit_word;
    reg done;

    wire [15:0] lfsr_state;
    wire [WAY_NUM_WIDTH-1:0] victim_way;
    assign victim_way = lfsr_state[WAY_NUM_WIDTH-1:0];

    // 仅在读 miss 时推进一次 LFSR（选择回填路）
    wire lfsr_advance = dmem_valid & dmem_ren & ~hit_found & ~pending_read_miss & ~pending_write_through;
    lfsr16_data u_lfsr16_data (
        .clk    (clk),
        .rst_n  (rst_n),
        .advance(lfsr_advance),
        .state  (lfsr_state)
    );

    // 根据 size/byte offset 做符号扩展读取（与 data_mem 语义对齐）
    function [31:0] cache_read_data;
        input [31:0] word_data;
        input [1:0]  size;
        input [1:0]  pos;
        begin
            case (size)
                2'b00: begin
                    case (pos)
                        2'b00: cache_read_data = {{24{word_data[7]}},  word_data[7:0]};
                        2'b01: cache_read_data = {{24{word_data[15]}}, word_data[15:8]};
                        2'b10: cache_read_data = {{24{word_data[23]}}, word_data[23:16]};
                        2'b11: cache_read_data = {{24{word_data[31]}}, word_data[31:24]};
                    endcase
                end
                2'b01: begin
                    case (pos)
                        2'b00: cache_read_data = {{16{word_data[15]}}, word_data[15:0]};
                        2'b10: cache_read_data = {{16{word_data[31]}}, word_data[31:16]};
                        default: cache_read_data = 32'h0;
                    endcase
                end
                2'b10: cache_read_data = word_data;
                default: cache_read_data = 32'h0;
            endcase
        end
    endfunction

    // 根据 size/byte offset 对字做局部写入
    function [31:0] cache_write_word;
        input [31:0] old_word;
        input [31:0] write_data;
        input [1:0]  size;
        input [1:0]  pos;
        begin
            cache_write_word = old_word;
            case (size)
                2'b00: begin
                    case (pos)
                        2'b00: cache_write_word[7:0]   = write_data[7:0];
                        2'b01: cache_write_word[15:8]  = write_data[7:0];
                        2'b10: cache_write_word[23:16] = write_data[7:0];
                        2'b11: cache_write_word[31:24] = write_data[7:0];
                    endcase
                end
                2'b01: begin
                    case (pos)
                        2'b00: cache_write_word[15:0]  = write_data[15:0];
                        2'b10: cache_write_word[31:16] = write_data[15:0];
                        default: cache_write_word = old_word;
                    endcase
                end
                2'b10: cache_write_word = write_data;
                default: cache_write_word = old_word;
            endcase
        end
    endfunction

    integer ri;
    integer rj;
    integer hj;
    reg [31:0] merged_word;
    reg [GROUP_NUM_WIDTH-1:0] req_group_index;
    reg [BLOCK_WIDTH-1:0] req_word_offset;
    reg [1:0] req_byte_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ri = 0; ri < (1 << GROUP_NUM_WIDTH); ri = ri + 1) begin
                for (rj = 0; rj < (1 << WAY_NUM_WIDTH); rj = rj + 1) begin
                    Cache_addr[ri][rj][MEM_ADDR_WIDTH] <= 1'b0;
                end
            end
            dmem_rdata_reg <= {DATA_SIZE_WIDTH{1'b0}};
            dmem_ready_reg <= 1'b0;
            mem_valid_reg <= 1'b0;
            mem_read_en_reg <= 1'b0;
            mem_write_en_reg <= 1'b0;
            mem_size_reg <= 2'b10;
            mem_addr_reg <= {MEM_ADDR_WIDTH{1'b0}};
            mem_wdata_reg <= {DATA_SIZE_WIDTH{1'b0}};
            pending_read_miss <= 1'b0;
            pending_write_through <= 1'b0;
            req_addr_reg <= {MEM_ADDR_WIDTH{1'b0}};
            req_wdata_reg <= {DATA_SIZE_WIDTH{1'b0}};
            req_size_reg <= 2'b10;
            req_is_read_reg <= 1'b0;
            refill_group_index <= {GROUP_NUM_WIDTH{1'b0}};
            refill_word_offset <= {BLOCK_WIDTH{1'b0}};
            refill_way <= {WAY_NUM_WIDTH{1'b0}};
        end else begin
            dmem_ready_reg <= 1'b0;

            req_group_index = req_addr_reg[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH];
            req_word_offset = req_addr_reg[BLOCK_WIDTH-1:0];
            req_byte_pos    = req_addr_reg[1:0];

            // 命中判定（仅对当前拍输入请求）
            hit_found = 1'b0;
            hit_way = {WAY_NUM_WIDTH{1'b0}};
            hit_word = 32'b0;
            done = 1'b0;
            if (dmem_valid && (dmem_ren || dmem_wen) && !pending_read_miss && !pending_write_through) begin
                for (hj = 0; hj < (1 << WAY_NUM_WIDTH) && !done; hj = hj + 1) begin
                    if (Cache_addr[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH] == 1'b1 &&
                        Cache_addr[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][MEM_ADDR_WIDTH-1:BLOCK_WIDTH] == dmem_addr[MEM_ADDR_WIDTH-1:BLOCK_WIDTH]) begin
                        case (dmem_addr[BLOCK_WIDTH-1:2])
                            2'd0: hit_word = Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][31:0];
                            2'd1: hit_word = Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][63:32];
                            2'd2: hit_word = Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][95:64];
                            2'd3: hit_word = Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hj][127:96];
                            default: hit_word = 32'b0;
                        endcase
                        hit_way = hj[WAY_NUM_WIDTH-1:0];
                        hit_found = 1'b1;
                        done = 1'b1;
                    end
                end
            end

            if (pending_read_miss || pending_write_through) begin
                mem_valid_reg    <= 1'b1;
                mem_read_en_reg  <= req_is_read_reg;
                mem_write_en_reg <= ~req_is_read_reg;
                mem_size_reg     <= req_size_reg;
                mem_addr_reg     <= req_addr_reg;
                mem_wdata_reg    <= req_wdata_reg;

                if (mem_ready) begin
                    if (pending_read_miss) begin
                        // 回填 miss 字所在位置
                        Cache_addr[refill_group_index][refill_way][MEM_ADDR_WIDTH] <= 1'b1;
                        Cache_addr[refill_group_index][refill_way][MEM_ADDR_WIDTH-1:0] <=
                            {req_addr_reg[MEM_ADDR_WIDTH-1:BLOCK_WIDTH], {BLOCK_WIDTH{1'b0}}};
                        case (refill_word_offset[BLOCK_WIDTH-1:2])
                            2'd0: Cache_data[refill_group_index][refill_way][31:0]   <= mem_rdata;
                            2'd1: Cache_data[refill_group_index][refill_way][63:32]  <= mem_rdata;
                            2'd2: Cache_data[refill_group_index][refill_way][95:64]  <= mem_rdata;
                            2'd3: Cache_data[refill_group_index][refill_way][127:96] <= mem_rdata;
                            default: Cache_data[refill_group_index][refill_way][31:0] <= mem_rdata;
                        endcase
                        dmem_rdata_reg <= cache_read_data(mem_rdata, req_size_reg, req_byte_pos);
                    end
                    dmem_ready_reg <= 1'b1;
                    mem_valid_reg <= 1'b0;
                    mem_read_en_reg <= 1'b0;
                    mem_write_en_reg <= 1'b0;
                    pending_read_miss <= 1'b0;
                    pending_write_through <= 1'b0;
                end
            end else begin
                mem_valid_reg <= 1'b0;
                mem_read_en_reg <= 1'b0;
                mem_write_en_reg <= 1'b0;

                if (dmem_valid && dmem_ren) begin
                    if (hit_found) begin
                        dmem_rdata_reg <= cache_read_data(hit_word, dmem_size, dmem_addr[1:0]);
                        dmem_ready_reg <= 1'b1;
                    end else begin
                        // 读 miss：下行读 + 回填
                        req_addr_reg <= dmem_addr;
                        req_wdata_reg <= 32'b0;
                        req_size_reg <= 2'b10; // 回填总是按字读取
                        req_is_read_reg <= 1'b1;
                        refill_group_index <= dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH];
                        refill_word_offset <= dmem_addr[BLOCK_WIDTH-1:0];
                        refill_way <= victim_way;
                        pending_read_miss <= 1'b1;
                        mem_valid_reg <= 1'b1;
                        mem_read_en_reg <= 1'b1;
                        mem_size_reg <= 2'b10;
                        mem_addr_reg <= dmem_addr;
                    end
                end else if (dmem_valid && dmem_wen) begin
                    // 写直达：命中先改 cache，再向下层写
                    if (hit_found) begin
                        merged_word = cache_write_word(hit_word, dmem_wdata, dmem_size, dmem_addr[1:0]);
                        case (dmem_addr[BLOCK_WIDTH-1:2])
                            2'd0: Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hit_way][31:0]   <= merged_word;
                            2'd1: Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hit_way][63:32]  <= merged_word;
                            2'd2: Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hit_way][95:64]  <= merged_word;
                            2'd3: Cache_data[dmem_addr[BLOCK_WIDTH + GROUP_NUM_WIDTH - 1:BLOCK_WIDTH]][hit_way][127:96] <= merged_word;
                        endcase
                    end

                    req_addr_reg <= dmem_addr;
                    req_wdata_reg <= dmem_wdata;
                    req_size_reg <= dmem_size;
                    req_is_read_reg <= 1'b0;
                    pending_write_through <= 1'b1;

                    mem_valid_reg <= 1'b1;
                    mem_read_en_reg <= 1'b0;
                    mem_write_en_reg <= 1'b1;
                    mem_size_reg <= dmem_size;
                    mem_addr_reg <= dmem_addr;
                    mem_wdata_reg <= dmem_wdata;
                end
            end
        end
    end

endmodule
