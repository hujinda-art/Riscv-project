// ============================================================================
// soc_addr_map.vh  --  统一地址映射（预留外设槽位；当前 RTL 多为直连未译码）
// 可单独 `include；若尚未包含 soc_config.vh，此处自动拉入。
// ============================================================================
`ifndef SOC_ADDR_MAP_VH
`define SOC_ADDR_MAP_VH
`ifndef SOC_CONFIG_VH
`include "soc_config.vh"
`endif

// ---- 指令空间（哈佛结构取指口视角）----
`define SOC_IMEM_BASE           32'h0000_0000
`define SOC_IMEM_SIZE_BYTES     ((1 << (`SOC_IMEM_ADDR_WIDTH + 2)))

// ---- 数据空间（当前核访存直连单口 data_mem，软件常用 0(x0)；
//      下列 BASE 供链接脚本/后续译码扩展对齐，不等同于“已接多从设备”）----
`define SOC_DMEM_BASE           32'h0000_0000
`define SOC_DMEM_SIZE_BYTES     ((1 << (`SOC_DMEM_ADDR_WIDTH + 2)))

// ---- 预留外设区（与 new.md 示例一致，便于后续 subsys_perips）----
`define SOC_GPIO_BASE           32'h1000_0000
`define SOC_UART_BASE           32'h1000_1000
`define SOC_TIMER_BASE          32'h0200_0000

`endif // SOC_ADDR_MAP_VH
