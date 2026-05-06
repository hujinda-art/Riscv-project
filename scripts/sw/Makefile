# ============================================================================
#  scripts/sw/Makefile — RISC-V 裸机固件统一编译入口
#
# 用法（在 scripts/sw 目录下）：
#   make          — 编译默认目标（full_instr.hex + .dump）
#   make tb       — 一次生成 tb_fwd.hex + tb_mem.hex
#   make fwd      — 仅 tb_fwd.hex（前递/BLT 定向测试）
#   make mem      — 仅 tb_mem.hex（LW/SW 定向测试）
#   make sw-lw    — 仅 tb_sw_lw_raw.hex（SW→LW RAW hazard 测试）
#   make hello    — 仅 uart_hello.hex（UART "Hi" 循环）
#   make sum100   — 仅 sum1to100.hex（1+...+100 求和）
#   make matmul   — 仅 matmul.hex（4x4 矩阵乘法）
#   make clean    — 删除 build/
#   make help     — 打印本帮助
#
# ISA 选择：
#   make RV_MARCH=rv32im    — 启用 M 扩展编译
#   make CROSS=riscv64-unknown-elf-  — 自定义交叉编译前缀
# ============================================================================

# ---- 工具链 ---------------------------------------------------------------
CROSS    ?= riscv64-unknown-elf
CC       := $(CROSS)-gcc
OBJCOPY  := $(CROSS)-objcopy
OBJDUMP  := $(CROSS)-objdump
PYTHON   ?= python3

# ---- 编译选项 -------------------------------------------------------------
RV_MARCH ?= rv32i
CFLAGS   := -march=$(RV_MARCH) -mabi=ilp32 -O2 \
            -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wall -Wextra
LDFLAGS  := -T link.ld -nostdlib -nostartfiles -Wl,--gc-sections -lgcc

BUILD_DIR := build

# ---- 全局依赖 -------------------------------------------------------------
$(BUILD_DIR):
	mkdir -p $@

# ============================================================================
# 目标定义：名称 _ELM / _BIN / _HEX / _SRCS / _FLAGS（定向测试用 -O0）
# ============================================================================

# --- full_instr（默认：全指令自测）------------------------------------------
FULL_SRCS := startup.S full_instr_test.c
FULL_ELF  := $(BUILD_DIR)/full_instr.elf
FULL_BIN  := $(BUILD_DIR)/full_instr.bin
FULL_HEX  := $(BUILD_DIR)/full_instr.hex
FULL_DUMP := $(BUILD_DIR)/full_instr.dump

# --- tb_fwd（前递 + BLT 分支）----------------------------------------------
FWD_SRCS  := startup.S tb_fwd_hazard.S
FWD_FLAGS := $(subst -O2,-O0,$(CFLAGS))
FWD_ELF   := $(BUILD_DIR)/tb_fwd.elf
FWD_BIN   := $(BUILD_DIR)/tb_fwd.bin
FWD_HEX   := $(BUILD_DIR)/tb_fwd.hex

# --- tb_mem（LW/SW、字/半字/字节）------------------------------------------
MEM_SRCS  := startup.S tb_mem_loadstore.S
MEM_FLAGS := $(subst -O2,-O0,$(CFLAGS))
MEM_ELF   := $(BUILD_DIR)/tb_mem.elf
MEM_BIN   := $(BUILD_DIR)/tb_mem.bin
MEM_HEX   := $(BUILD_DIR)/tb_mem.hex

# --- tb_sw_lw_raw（SW→LW RAW hazard）---------------------------------------
SWLW_SRCS  := startup.S tb_sw_lw_raw.S
SWLW_FLAGS := $(subst -O2,-O0,$(CFLAGS))
SWLW_ELF   := $(BUILD_DIR)/tb_sw_lw_raw.elf
SWLW_BIN   := $(BUILD_DIR)/tb_sw_lw_raw.bin
SWLW_HEX   := $(BUILD_DIR)/tb_sw_lw_raw.hex

# --- uart_hello（UART "Hi\r\n" 循环）----------------------------------------
HELLO_SRCS := startup.S uart_hello.S
HELLO_ELF  := $(BUILD_DIR)/uart_hello.elf
HELLO_BIN  := $(BUILD_DIR)/uart_hello.bin
HELLO_HEX  := $(BUILD_DIR)/uart_hello.hex

# --- sum1to100（1+...+100=5050 求和 UART 输出）-------------------------------
SUM_SRCS   := startup.S sum1to100.S
SUM_ELF    := $(BUILD_DIR)/sum1to100.elf
SUM_BIN    := $(BUILD_DIR)/sum1to100.bin
SUM_HEX    := $(BUILD_DIR)/sum1to100.hex

# --- matmul（4x4 矩阵乘法 UART 输出）----------------------------------------
MATMUL_SRCS := startup.S matmul_test.c
MATMUL_ELF  := $(BUILD_DIR)/matmul.elf
MATMUL_BIN  := $(BUILD_DIR)/matmul.bin
MATMUL_HEX  := $(BUILD_DIR)/matmul.hex

# ============================================================================
# 构建规则
# ============================================================================

# ---- 默认目标 -------------------------------------------------------------
all: $(FULL_HEX) $(FULL_DUMP)

tb: $(FWD_HEX) $(MEM_HEX)
	@echo "OK: $(FWD_HEX)  $(MEM_HEX)"

# ---- 通用 ELF / BIN / HEX 配方 --------------------------------------------

# full_instr（C + asm，-O2 + dump）
$(FULL_ELF): $(FULL_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(FULL_SRCS) $(LDFLAGS) -o $@
$(FULL_BIN): $(FULL_ELF)
	$(OBJCOPY) -O binary $< $@
$(FULL_HEX): $(FULL_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@
$(FULL_DUMP): $(FULL_ELF)
	$(OBJDUMP) -d $< > $@

# tb_fwd（纯 asm，-O0 保证 main 首条对齐指纹地址）
$(FWD_ELF): $(FWD_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(FWD_FLAGS) $(FWD_SRCS) $(LDFLAGS) -o $@
$(FWD_BIN): $(FWD_ELF)
	$(OBJCOPY) -O binary $< $@
$(FWD_HEX): $(FWD_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# tb_mem（纯 asm，-O0）
$(MEM_ELF): $(MEM_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(MEM_FLAGS) $(MEM_SRCS) $(LDFLAGS) -o $@
$(MEM_BIN): $(MEM_ELF)
	$(OBJCOPY) -O binary $< $@
$(MEM_HEX): $(MEM_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# tb_sw_lw_raw（纯 asm，-O0）
$(SWLW_ELF): $(SWLW_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(SWLW_FLAGS) $(SWLW_SRCS) $(LDFLAGS) -o $@
$(SWLW_BIN): $(SWLW_ELF)
	$(OBJCOPY) -O binary $< $@
$(SWLW_HEX): $(SWLW_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# uart_hello（纯 asm，-O2）
$(HELLO_ELF): $(HELLO_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(HELLO_SRCS) $(LDFLAGS) -o $@
$(HELLO_BIN): $(HELLO_ELF)
	$(OBJCOPY) -O binary $< $@
$(HELLO_HEX): $(HELLO_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# sum1to100（纯 asm，-O2）
$(SUM_ELF): $(SUM_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SUM_SRCS) $(LDFLAGS) -o $@
$(SUM_BIN): $(SUM_ELF)
	$(OBJCOPY) -O binary $< $@
$(SUM_HEX): $(SUM_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# matmul（C + asm，-O2）
$(MATMUL_ELF): $(MATMUL_SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(MATMUL_SRCS) $(LDFLAGS) -o $@
$(MATMUL_BIN): $(MATMUL_ELF)
	$(OBJCOPY) -O binary $< $@
$(MATMUL_HEX): $(MATMUL_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# ============================================================================
# Phony 快捷目标
# ============================================================================

fwd:    $(FWD_HEX)
	@echo "OK: $<"
mem:    $(MEM_HEX)
	@echo "OK: $<"
sw-lw:  $(SWLW_HEX)
	@echo "OK: $<"
hello:  $(HELLO_HEX)
	@echo "OK: $<"
sum100: $(SUM_HEX)
	@echo "OK: $<"
matmul: $(MATMUL_HEX)
	@echo "OK: $<"

# ============================================================================
# 帮助
# ============================================================================
help:
	@echo "用法（在 scripts/sw 目录执行）："
	@echo "  make          — 编译 full_instr（完整自测）"
	@echo "  make tb       — 一次生成 tb_fwd.hex + tb_mem.hex（定向仿真）"
	@echo "  make fwd      — 仅 tb_fwd.hex（前递/BLT）"
	@echo "  make mem      — 仅 tb_mem.hex（LW/SW）"
	@echo "  make sw-lw    — 编译 tb_sw_lw_raw.hex（SW→LW RAW hazard）"
	@echo "  make hello    — 编译 uart_hello.hex（UART "Hi" 循环）"
	@echo "  make sum100   — 编译 sum1to100.hex（1+...+100=5050 求和）"
	@echo "  make matmul   — 编译 matmul.hex（4x4 矩阵乘法）"
	@echo "  make clean    — 删除 build/"
	@echo "  make help     — 打印本帮助"
	@echo ""
	@echo "交叉编译前缀：CROSS=$(CROSS)"
	@echo "  make tb CROSS=riscv64-unknown-elf-"
	@echo ""
	@echo "ISA 选择：RV_MARCH=$(RV_MARCH)"
	@echo "  make RV_MARCH=rv32im    — 启用 M 扩展编译"

# ============================================================================
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean tb fwd mem sw-lw hello sum100 matmul help
