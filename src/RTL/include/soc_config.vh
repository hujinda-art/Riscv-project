// ============================================================================
// soc_config.vh  --  SoC / 核侧统一配置
// 用法：在模块文件顶部 `include 本文件；勿在多个 define 冲突处重复定义。
// ============================================================================
`ifndef SOC_CONFIG_VH
`define SOC_CONFIG_VH

// ---- 体系结构 ----
`define SOC_XLEN                32
`define SOC_RESET_VECTOR        32'h0000_0000

// ---- 片内存储深度（字地址宽度 = log2(字数)；字节容量 = 2^(W+2)）----
`define SOC_IMEM_ADDR_WIDTH     10
`define SOC_DMEM_ADDR_WIDTH     10

// ---- 访存宽度编码（与 LSU / data_mem 的 size 端口一致）----
`define SOC_MEM_SIZE_WORD       2'b10

// ---- 理想总线：当前 soc_top 将 rvalid 恒置 1；后续握手总线可改此宏 ----
`define SOC_IDEAL_IMEM_RVALID   1'b1
`define SOC_IDEAL_DMEM_READY    1'b1

// ---- 字对齐寻址：字节地址中字索引区间 [MSB:2]（MSB = ADDR_WIDTH+1）----
`define SOC_MEM_WORD_INDEX_LSB  2

// ---- Cache 参数配置 ----
// CACHE_BLOCK_BYTE_SIZE_WIDTH：log2(块字节数)，块大小 = 2^W 字节
`define CACHE_BLOCK_BYTE_SIZE_WIDTH 4 // 16 字节 / 行
// 以下两项为「索引/路选」**位宽**，不是十进制组数/路数：组数=2^Wset，路数=2^Wway
`define CACHE_BLOCK_NUMBER 4 // 组索引 4 位 → 16 组
`define CACHE_BLOCK_WAY_NUMBER 2 // 路选 2 位 → 4 路
`define CACHE_BLOCK_TAG_BYTE_WIDTH 25
`endif // SOC_CONFIG_VH

//数据位宽
`define DATA_SIZE 32

//指令位宽
`define INSTR_SIZE 32

//地址位宽
`define MEM_ADDR_WIDTH 32