# 裸机嵌入式前缀 → riscv64-unknown-elf-gcc；勿与 riscv64-unknown-linux-gnu- 混用
CROSS ?= riscv64-unknown-elf
CC := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump
PYTHON ?= python3

# 当前 RTL 未实现 M/C 时保持 rv32i；实现 M 后改为 rv32im：make RV_MARCH=rv32im
RV_MARCH ?= rv32i
CFLAGS := -march=$(RV_MARCH) -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wall -Wextra
LDFLAGS := -T link.ld -nostdlib -nostartfiles -Wl,--gc-sections -lgcc

BUILD_DIR := build
ELF := $(BUILD_DIR)/full_instr.elf
BIN := $(BUILD_DIR)/full_instr.bin
HEX := $(BUILD_DIR)/full_instr.hex
DUMP := $(BUILD_DIR)/full_instr.dump

SRCS := startup.S full_instr_test.c

# 定向仿真用最小 hex（与 sim/testbench/tb_fwd_hazard.v、tb_mem_loadstore.v 配套）
TB_FWD_ELF  := $(BUILD_DIR)/tb_fwd.elf
TB_FWD_BIN  := $(BUILD_DIR)/tb_fwd.bin
TB_FWD_HEX  := $(BUILD_DIR)/tb_fwd.hex
TB_MEM_ELF  := $(BUILD_DIR)/tb_mem.elf
TB_MEM_BIN  := $(BUILD_DIR)/tb_mem.bin
TB_MEM_HEX  := $(BUILD_DIR)/tb_mem.hex

# 默认：完整自测程序 full_instr.hex
all: $(HEX) $(DUMP)

# 一条命令生成两个定向测试 hex（最简用法：在 scripts/sw 下执行  make tb ）
tb: $(TB_FWD_HEX) $(TB_MEM_HEX)
	@echo "OK: $(TB_FWD_HEX)  $(TB_MEM_HEX)"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): $(SRCS) link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SRCS) $(LDFLAGS) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN) bin2hex.py
	$(PYTHON) bin2hex.py $(BIN) $(HEX)

$(DUMP): $(ELF)
	$(OBJDUMP) -d $< > $@

# 定向测试用 -O0，保证 main 首条仍落在 0x10 且 IMEM[4] 与 TB 指纹一致
$(TB_FWD_ELF): startup.S tb_fwd_hazard.S link.ld | $(BUILD_DIR)
	$(CC) $(subst -O2,-O0,$(CFLAGS)) startup.S tb_fwd_hazard.S $(LDFLAGS) -o $@

$(TB_FWD_BIN): $(TB_FWD_ELF)
	$(OBJCOPY) -O binary $< $@

$(TB_FWD_HEX): $(TB_FWD_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

$(TB_MEM_ELF): startup.S tb_mem_loadstore.S link.ld | $(BUILD_DIR)
	$(CC) $(subst -O2,-O0,$(CFLAGS)) startup.S tb_mem_loadstore.S $(LDFLAGS) -o $@

$(TB_MEM_BIN): $(TB_MEM_ELF)
	$(OBJCOPY) -O binary $< $@

$(TB_MEM_HEX): $(TB_MEM_BIN) bin2hex.py
	$(PYTHON) bin2hex.py $< $@

# 短别名（与 tb 子目标等价）
tb-fwd-hex fwd: $(TB_FWD_HEX)
tb-mem-hex mem: $(TB_MEM_HEX)

help:
	@echo "用法（在 scripts/sw 目录执行）："
	@echo "  make          — 编译 full_instr（完整自测）"
	@echo "  make tb       — 一次生成 tb_fwd.hex + tb_mem.hex（定向仿真）"
	@echo "  make fwd      — 仅 tb_fwd.hex（前递/BLT）"
	@echo "  make mem      — 仅 tb_mem.hex（LW/SW）"
	@echo "  make clean    — 删除 build/"
	@echo "交叉编译前缀: CROSS=$(CROSS)  （例: make tb CROSS=riscv64-unknown-elf）"
	@echo "ISA: RV_MARCH=$(RV_MARCH)  （实现 M 扩展后: make RV_MARCH=rv32im）"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean tb tb-fwd-hex tb-mem-hex fwd mem help
