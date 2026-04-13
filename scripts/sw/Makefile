CROSS ?= riscv64-unknown-elf
CC := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump
PYTHON ?= python3

CFLAGS := -march=rv32im -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wall -Wextra
LDFLAGS := -T link.ld -nostdlib -nostartfiles -Wl,--gc-sections

BUILD_DIR := build
ELF := $(BUILD_DIR)/full_instr.elf
BIN := $(BUILD_DIR)/full_instr.bin
HEX := $(BUILD_DIR)/full_instr.hex
DUMP := $(BUILD_DIR)/full_instr.dump

SRCS := startup.S full_instr_test.c

all: $(HEX) $(DUMP)

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

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean
