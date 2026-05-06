# ============================================================================
# sim/verilator/Makefile — Verilator simulation for all existing testbenches
#
# All DUTs use `include for submodules. Verilator only needs the top-level
# .v file plus include search paths.
#
# Usage:
#   make all        - compile and run ALL tests
#   make clean      - remove build artifacts
# ============================================================================

VERILATOR  ?= verilator
CXX        ?= g++
PROJ_ROOT  := $(realpath ../..)
WAVEFORM_DIR := $(PROJ_ROOT)/sim/waveform
TB_DIR     := $(PROJ_ROOT)/sim/verilator

# Include search paths for `include resolution
V_INC = -I$(PROJ_ROOT)/src/RTL/include \
        -I$(PROJ_ROOT)/src/RTL/core \
        -I$(PROJ_ROOT)/src/RTL/module \
        -I$(PROJ_ROOT)/src/RTL/module/ALU \
        -I$(PROJ_ROOT)/src/RTL/module/PC \
        -I$(PROJ_ROOT)/src/RTL/module/Cache \
        -I$(PROJ_ROOT)/src/RTL/memory

# Common Verilator flags
V_FLAGS_BASE = --cc --exe --build --trace --public-flat-rw \
               -Wno-fatal -Wno-UNUSED -Wno-UNDRIVEN -Wno-PINMISSING \
               -Wno-MODDUP -Wno-IMPLICIT \
               -CFLAGS "-std=c++14 -I$(TB_DIR)"

# ============================================================================
# Hex file paths
# ============================================================================
HEX_SYS = $(PROJ_ROOT)/scripts/sw/build/full_instr.hex
HEX_FWD = $(PROJ_ROOT)/scripts/sw/build/tb_fwd.hex
HEX_MEM = $(PROJ_ROOT)/scripts/sw/build/tb_mem.hex

# ============================================================================
# Phony targets
# ============================================================================
.PHONY: all clean \
        test_sys test_fwd test_mem test_jump test_jump_nm test_feat \
        test_mext test_dcache test_icache test_alu test_l1i

all: test_sys test_fwd test_mem test_jump test_jump_nm test_feat \
     test_mext test_dcache test_icache test_alu test_l1i
	@echo ""
	@echo "============================================"
	@echo "  All Verilator tests complete"
	@echo "  Waveforms in: $(WAVEFORM_DIR)/"
	@echo "============================================"

# ============================================================================
# soc_top_bram — top-level file only; includes bring in the rest
# ============================================================================
build/Vsoc_top_bram: $(TB_DIR)/tb_soc_top_bram.cpp
	@mkdir -p build/soc_bram
	$(VERILATOR) $(V_FLAGS_BASE) $(V_INC) --Mdir build/soc_bram \
	    --top-module soc_top_bram \
	    $(PROJ_ROOT)/src/RTL/core/soc_top_bram.v \
	    --exe $(TB_DIR)/tb_soc_top_bram.cpp
	cp build/soc_bram/Vsoc_top_bram build/Vsoc_top_bram

test_sys: build/Vsoc_top_bram
	@echo "=== tb_system_soc ==="
	./build/Vsoc_top_bram +TEST=system +HEX=$(HEX_SYS) +WAVE=$(WAVEFORM_DIR)/tb_system_soc.vcd || true

test_fwd: build/Vsoc_top_bram
	@echo "=== tb_fwd_hazard ==="
	./build/Vsoc_top_bram +TEST=fwd +HEX=$(HEX_FWD) +WAVE=$(WAVEFORM_DIR)/tb_fwd_hazard.vcd || true

test_mem: build/Vsoc_top_bram
	@echo "=== tb_mem_loadstore ==="
	./build/Vsoc_top_bram +TEST=mem +HEX=$(HEX_MEM) +WAVE=$(WAVEFORM_DIR)/tb_mem_loadstore.vcd || true

test_jump: build/Vsoc_top_bram
	@echo "=== core_jump_tb ==="
	./build/Vsoc_top_bram +TEST=core_jump +WAVE=$(WAVEFORM_DIR)/core_jump_tb.vcd || true

test_jump_nm: build/Vsoc_top_bram
	@echo "=== tb_jump_no_mem ==="
	./build/Vsoc_top_bram +TEST=jump_no_mem +WAVE=$(WAVEFORM_DIR)/tb_jump_no_mem.vcd || true

test_feat: build/Vsoc_top_bram
	@echo "=== special_features_tb ==="
	./build/Vsoc_top_bram +TEST=special_features +WAVE=$(WAVEFORM_DIR)/special_features_tb.vcd || true

# ============================================================================
# soc_top_bram_dcache
# ============================================================================
build/Vsoc_top_bram_dcache: $(TB_DIR)/tb_soc_top_bram_dcache.cpp
	@mkdir -p build/soc_dcache
	$(VERILATOR) $(V_FLAGS_BASE) $(V_INC) --Mdir build/soc_dcache \
	    --top-module soc_top_bram_dcache \
	    $(PROJ_ROOT)/src/RTL/core/soc_top_bram_dcache.v \
	    --exe $(TB_DIR)/tb_soc_top_bram_dcache.cpp
	cp build/soc_dcache/Vsoc_top_bram_dcache build/Vsoc_top_bram_dcache

test_mext: build/Vsoc_top_bram_dcache
	@echo "=== tb_m_extension ==="
	./build/Vsoc_top_bram_dcache +TEST=m_extension +WAVE=$(WAVEFORM_DIR)/tb_m_extension.vcd || true

test_dcache: build/Vsoc_top_bram_dcache
	@echo "=== tb_dcache_sys ==="
	./build/Vsoc_top_bram_dcache +TEST=dcache_sys +WAVE=$(WAVEFORM_DIR)/tb_dcache_sys.vcd || true

# ============================================================================
# soc_top_bram_icache
# ============================================================================
build/Vsoc_top_bram_icache: $(TB_DIR)/tb_soc_top_bram_icache.cpp
	@mkdir -p build/soc_icache
	$(VERILATOR) $(V_FLAGS_BASE) $(V_INC) --Mdir build/soc_icache \
	    --top-module soc_top_bram_icache \
	    $(PROJ_ROOT)/src/RTL/core/soc_top_bram_icache.v \
	    --exe $(TB_DIR)/tb_soc_top_bram_icache.cpp
	cp build/soc_icache/Vsoc_top_bram_icache build/Vsoc_top_bram_icache

test_icache: build/Vsoc_top_bram_icache
	@echo "=== tb_icache_sys ==="
	./build/Vsoc_top_bram_icache +TEST=icache_sys +WAVE=$(WAVEFORM_DIR)/tb_icache_sys.vcd || true

# ============================================================================
# ALU — standalone module (includes submodules via `include)
# ============================================================================
build/VALU: $(TB_DIR)/tb_alu.cpp
	@mkdir -p build/alu
	$(VERILATOR) $(V_FLAGS_BASE) -I$(PROJ_ROOT)/src/RTL/module/ALU \
	    --Mdir build/alu --top-module ALU \
	    $(PROJ_ROOT)/src/RTL/module/ALU/ALU.v \
	    --exe $(TB_DIR)/tb_alu.cpp
	cp build/alu/VALU build/VALU

test_alu: build/VALU
	@echo "=== ALU_test ==="
	./build/VALU +WAVE=$(WAVEFORM_DIR)/alu_test.vcd || true

# ============================================================================
# L1_Cache_INST — standalone module (includes LFSR16_inst.v)
# ============================================================================
build/VL1_Cache_INST: $(TB_DIR)/tb_l1_cache.cpp
	@mkdir -p build/l1cache
	$(VERILATOR) $(V_FLAGS_BASE) $(V_INC) \
	    --Mdir build/l1cache --top-module L1_Cache_INST \
	    $(PROJ_ROOT)/src/RTL/module/Cache/L1_Cache_INST.v \
	    --exe $(TB_DIR)/tb_l1_cache.cpp
	cp build/l1cache/VL1_Cache_INST build/VL1_Cache_INST

test_l1i: build/VL1_Cache_INST
	@echo "=== tb_L1_Cache_INST ==="
	./build/VL1_Cache_INST +WAVE=$(WAVEFORM_DIR)/tb_L1_Cache_INST.vcd || true

# ============================================================================
clean:
	rm -rf build
