## ============================================================
## fpga_top_bram.xdc — Basys3 约束文件（BRAM 直连路径，无 Cache，无 AXI）
##
## 对应顶层：src/RTL/core/fpga_top_bram.v
## 架构：core_top → inst_mem (片上 ROM)
##                  → data_mem (片上 BRAM)
##
## 使用方法：在 Vivado 工程中仅需加入 RTL 源文件，无需 BD
##   源文件清单参见 fpga_top_bram.v 头部注释
## ============================================================

# ---- 100MHz 系统时钟 (Basys3: W5) ----
set_property PACKAGE_PIN W5   [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

# ---- 复位按钮 (Basys3: BTNU = V17, 按下为高电平) ----
# BTNU 按下时输出高电平；FPGA 顶层 (fpga_top_bram.v) 内部通过
#   wire sys_rst_n = ~rst_n;
# 反相后送给 SoC，实现「按下→复位，松开→运行」。
set_property PACKAGE_PIN V17  [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ---- LED 输出 (Basys3: LD7..LD0) ----
# led[7:0] 显示 ex_result_out 低 8 位
set_property PACKAGE_PIN U16  [get_ports {led[0]}]
set_property PACKAGE_PIN E19  [get_ports {led[1]}]
set_property PACKAGE_PIN U19  [get_ports {led[2]}]
set_property PACKAGE_PIN V19  [get_ports {led[3]}]
set_property PACKAGE_PIN W18  [get_ports {led[4]}]
set_property PACKAGE_PIN U15  [get_ports {led[5]}]
set_property PACKAGE_PIN U14  [get_ports {led[6]}]
set_property PACKAGE_PIN V14  [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ---- USB-UART TX (Basys3: A18, FPGA→FTDI) ----
set_property PACKAGE_PIN A18  [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
