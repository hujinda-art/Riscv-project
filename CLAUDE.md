# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a 32-bit RISC-V CPU core (RV32I/IM) with a 5-stage pipeline, L1 instruction cache, and optional AXI4 memory interface for FPGA (Xilinx Vivado BD). The project targets a competition (赛事) with riscv-tests compatibility.

## Build & Test Commands

### Software (cross-compile)
All firmware lives under `scripts/sw/`. Requires `riscv64-unknown-elf-gcc` in PATH.

```bash
cd scripts/sw

# Full instruction self-test (default target)
make
# Generates build/full_instr.hex, .elf, .dump

# Directed simulation hexes (forwarding/hazard + load/store)
make tb          # both tb_fwd.hex + tb_mem.hex
make fwd         # only tb_fwd.hex
make mem         # only tb_mem.hex

# With M extension (if RTL implements it)
make RV_MARCH=rv32im

# Clean
cd scripts/sw && make clean
```

### CoreMark benchmark
```bash
cd scripts/coremark
make PORT_DIR=riscv_soc link
# Produces coremark.elf; convert to hex manually if needed for RTL sim
```

### Simulation (testbenches)
Testbenches use `soc_top_bram` (CPU + on-chip BRAM, no AXI). They are plain Verilog; use Vivado Simulator, Icarus, or Verilator.

| Testbench | Purpose | Key plusarg |
|-----------|---------|-------------|
| `sim/system_testbench/tb_system_soc.v` | Full instruction system test vs `full_instr_test.c` signatures | `-testplusarg IMEM_HEX=<path>` |
| `sim/feat_testbench/tb_fwd_hazard.v` | Directed: EX forwarding + BLT branch | `-testplusarg IMEM_HEX=<path>` |
| `sim/feat_testbench/tb_mem_loadstore.v` | Directed: LW/SW + writeback + DONE | `-testplusarg IMEM_HEX=<path>` |
| `sim/feat_testbench/core_jump_tb.v` | JAL jump target + squash verification | — |
| `sim/feat_testbench/special_features_tb.v` | 7 special architectural features (JAL early resolve, dual WB, load-lock, etc.) | — |
| `sim/module_testbench/ALU_test.v` | ALU unit test | — |
| `sim/module_testbench/tb_L1_Cache_INST.v` | L1 I$ cold-miss, hit, multi-way, slow-mem | — |

Example Vivado Simulator CLI:
```bash
xelab -debug typical tb_system_soc -s tb_system_soc_sim
xsim tb_system_soc_sim -testplusarg IMEM_HEX=F:/Riscv-project/scripts/sw/build/full_instr.hex
```

### FPGA
- Top for pure RTL BRAM: `src/RTL/core/fpga_top.v` with `+define+FPGA_TOP_BRAM` → instantiates `soc_top_bram`.
- Top for Vivado BD + AXI: `fpga_top.v` without that define → instantiates `soc_top` + `soc_wrapper` (BD generated).
- Constraints template: `constraints/fpga_top.xdc` (Basys3 / Nexys A7 pinout examples).
- BD sources: `src/bd/soc/hdl/soc_wrapper.v` and generated IP under `src/bd/soc/ip/`.

### CI
- `make test` runs `scripts/test/minimal_test.sh` (structure check only).
- `.github/workflows/ci.yml` is a minimal placeholder; real validation is via simulation.

## Architecture

### Pipeline stages
`IF → IF_ID_reg → ID → ID_EX_reg → EX → EX_MEM_reg / EX_WB_reg → MEM_WB_reg → WB_stage`

- **IF** (`IF.v` / `PC.v`): PC update priority = exception > interrupt > JALR > JAL > branch > predict > stall > PC+4. `imem_req` is always 1 (do not gate by `~imem_ready` to avoid deadlock).
- **ID** (`ID.v`): Pure combinational decode. Generates `imm_out`, `use_rs1/rs2`, `is_branch/jump/jalr/load/store`, `reg_write_en`.
- **EX** (`EX.v`): ALU, branch condition, JALR target, load/store address. Handles forwarding from `register_EX` (non-load result) and `register_EX` load-lock (pending load data).
- **MEM**: Mostly passthrough; actual memory is in `soc_top_bram` (`data_mem.v`) or AXI master (`axi_if_dmem_master.v`).
- **WB** (`WB_stage.v`): Dual write-back path selection — `EX_WB_reg` for ALU results, `MEM_WB_reg` for load data. `wb_is_load_in` chooses the source.

### Hazard control (`hazard_ctrl.v`)
- **Load-use hazard**: Detected when a load in EX (`load_lock_out`) has `rd` matching `id_rs1/rs2` of the instruction in ID. Stalls IF/ID and flushes ID/EX (1 bubble).
- **Branch/JALR hazard**: Resolved in EX; flushes IF/ID and ID/EX only. Instructions already in EX/MEM or later are NOT flushed.
- **JAL early resolve**: Detected in ID (`jump_if = id_is_jump && instr_valid_out`); redirects PC immediately and flushes ID/EX (but NOT during `mem_stall` to avoid killing a held store).
- **Memory stall**: `mem_stall = (exmem_mem_read_en_out | exmem_mem_write_en_out) & ~dmem_ready`. Stalls IF/ID, ID/EX, and back stages.

### Forwarding & custom lock registers
- **`register_EX`**: Holds the most recent EX result (`rd_reg` / `rd_data_reg`) for normal ALU forwarding. For loads, it locks the destination register (`rd_reg_load`) and asserts `load_lock_out` until `dmem_ready` arrives, then forwards the loaded data.
- **`register_MEM`**: A 2-stage shift chain (`load_status_1/2`) used to align synchronous memory read timing with the load-lock mechanism.

### Register file (`register.v`)
- BRAM-inferred (`ram_style = "block"`), synchronous read (1-cycle latency).
- **Dual write ports**: Port 2 (JAL link, `jal_link_we`) has higher priority than port 1 (WB). If both target different registers in the same cycle, port 1 is buffered one cycle. x0 is hardwired to zero.
- Read bypass: external bypass captures last write; output mux selects bypass when `raddr_q == waddr` of previous cycle.

### SoC top variants
- **`soc_top_bram.v`**: CPU + `inst_mem` (ROM with baked-in `inst_mem_program.vh`) + `data_mem` (byte-write BRAM). Used for RTL simulation and pure-BRAM FPGA builds.
- **`soc_top.v`**: CPU + `L1_Cache_INST` + `axi_if_imem_master` + `axi_if_dmem_master`. No on-chip memory; connects to Vivado BD AXI SmartConnect.

### L1 Instruction Cache (`L1_Cache_INST.v`)
- Set-associative (configurable via `soc_config.vh`), write-back, random replacement via LFSR.
- Block size = 16 bytes (4 words). Refill fetches 4 words sequentially from lower memory; on completion the line is written back and the next cycle the CPU re-fetches (hit).
- Cache parameters in `soc_config.vh`: `CACHE_BLOCK_BYTE_SIZE_WIDTH`, `CACHE_BLOCK_NUMBER` (group index bits), `CACHE_BLOCK_WAY_NUMBER` (way select bits).

### AXI interfaces
- **`axi_if_imem_master.v`**: Single-outstanding AXI4 read master (AR/R only). Translates `mem_req/addr` to AXI; returns `mem_rdata` + `mem_ready`.
- **`axi_if_dmem_master.v`**: Single-outstanding AXI4 read/write master (AW/W/B + AR/R). Handles both loads and stores; `dmem_ready` asserted after R-last or B-valid.

### Memory map (`soc_addr_map.vh`)
- Instruction space: `0x0000_0000` (Harvard view)
- Data space: `0x0000_0000` (current core uses direct-connect `data_mem`)
- Reserved peripherals: GPIO `0x1000_0000`, UART `0x1000_1000`, Timer `0x0200_0000`

### Software test conventions
- `full_instr_test.c` emits 18 signature words starting at `SIG_BASE_ADDR = 0x100`, then writes `DONE_MAGIC = 0xC001D00D` to `0x80`, then self-traps (`j .`).
- `tb_system_soc.v` checks IMEM[0] fingerprint (`0x00001117` = `auipc sp,0x1` from `startup.S`) to detect stale `inst_mem_program.vh`.
- `data_mem` is 4 byte BRAM lanes (`mem0..mem3`). In testbenches, read a word with little-endian assembly: `{mem3[wi], mem2[wi], mem1[wi], mem0[wi]}`.

## Key Files

| File | Role |
|------|------|
| `src/RTL/include/soc_config.vh` | Architecture params: XLEN, reset vector, IMEM/DMEM depth, cache params, ideal bus macros |
| `src/RTL/include/soc_addr_map.vh` | Address map constants |
| `src/RTL/core/core_top.v` | CPU core top (pipeline + hazard + regfile) |
| `src/RTL/core/soc_top_bram.v` | SoC with on-chip BRAM (sim/BRAM-FPGA) |
| `src/RTL/core/soc_top.v` | SoC with AXI master ports (BD-FPGA) |
| `src/RTL/core/fpga_top.v` | FPGA top: selects `soc_top_bram` or `soc_top` + BD wrapper |
| `src/RTL/memory/inst_mem_program.vh` | Baked-in instruction ROM image (keep in sync with `scripts/sw/build/full_instr.hex`) |
| `scripts/sw/Makefile` | Firmware build: `full_instr`, `tb_fwd`, `tb_mem` |
| `scripts/sw/link.ld` | Bare-metal linker script (4K ROM / 4K RAM at 0x0) |
| `scripts/coremark/riscv_soc/core_portme.mak` | CoreMark port build rules |

## Common Pitfalls

- `inst_mem_program.vh` must be regenerated after any C/assembly change: `cd scripts/sw && make`, then copy `build/full_instr.hex` contents into the `.vh` `mem[]` initial block.
- `register_EX.v` has a combinational self-reference in `store_lock_out` / `load_lock_out` (line 36-37) that may synthesize as a latch; be careful with tool warnings.
- The `EX_WB_reg` and `MEM_WB_reg` paths converge in `WB_stage.v`. If both assert simultaneously, `wb_is_load_in` selects `MEM_WB_reg`; ensure `exwb_reg_write_en` is cleared for loads to avoid double-write conflicts.
- Vivado BD wrapper (`soc_wrapper.v`) does not expose AXI ID ports; `fpga_top.v` ties `rid`/`bid` to 0 and drives fixed `arcache`/`awcache` = `4'b0011`.

# other

+ always reply with Chinese

+ the reply always start with Cecilia

+ describe your plan first before modify the code

  