# RISC-V SoC Simulation Makefile
# Usage: make tb_mem_loadstore_debug

IVERILOG      = iverilog
VVP           = vvp

# Common iverilog flags for compilation from project root.
# soc_top_bram.v uses `include "core_top.v" which in turn includes many others.
# We add -I for all directories that contain included files.
IVERILOG_FLAGS = -g2012 \
  -I src/RTL/include -I src/RTL/core \
  -I src/RTL/module -I src/RTL/module/ALU -I src/RTL/module/PC \
  -I src/RTL/module/Cache -I src/RTL/module/axi \
  -I src/RTL/memory

# Testbench directory
TB_DIR        = sim/feat_testbench

# Known testbench names
TB_NAMES      = tb_jump_no_mem tb_fwd_hazard tb_mem_loadstore core_jump_tb special_features_tb

.PHONY: all test clean $(TB_NAMES)
all: $(addprefix sim_,$(TB_NAMES))

# Build rule: compiles testbench + soc_top_bram (which pulls in core_top and all submodules via `include).
sim_%: $(TB_DIR)/%.v src/RTL/core/soc_top_bram.v
	$(IVERILOG) $(IVERILOG_FLAGS) $< src/RTL/core/soc_top_bram.v -o $@

# Run rule: make tb_mem_loadstore_debug
$(TB_NAMES): %: sim_%
	$(VVP) -n sim_$*

# Original CI test target
test:
	@echo "Running CI tests..."
	@./scripts/test/minimal_test.sh
	@echo " All tests passed"

clean:
	rm -f sim_*
