## ============================================================
## fpga_top.xdc  --  Constraint template for fpga_top
## Replace pin names with your actual board pinout before running Place.
## ============================================================

# ---- Clock ----
# Example: 100 MHz system clock on Nexys-A7 / Basys3
set_property PACKAGE_PIN W5   [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# ---- Reset (active-low) ----
# Example: on-board reset button
set_property PACKAGE_PIN V17  [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ---- LEDs [7:0] ----
# Example: Basys3 LD7..LD0
set_property PACKAGE_PIN U16  [get_ports {led[0]}]
set_property PACKAGE_PIN E19  [get_ports {led[1]}]
set_property PACKAGE_PIN U19  [get_ports {led[2]}]
set_property PACKAGE_PIN V19  [get_ports {led[3]}]
set_property PACKAGE_PIN W18  [get_ports {led[4]}]
set_property PACKAGE_PIN U15  [get_ports {led[5]}]
set_property PACKAGE_PIN U14  [get_ports {led[6]}]
set_property PACKAGE_PIN V14  [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## ============================================================
## If you have a different board, replace PACKAGE_PIN values above.
## Common boards:
##   Nexys A7-100T : clk=E3, rst_n=CPU_RESETN=C12, led[0]=H17..
##   PYNQ-Z2       : clk=H16, rst_n=D9
## ============================================================
