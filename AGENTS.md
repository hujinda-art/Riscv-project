# AGENTS.md

本文件为 AI 编程助手提供项目背景、构建方式、代码组织与常见陷阱。阅读者应对本项目一无所知，因此所有关键信息均在此集中说明。

---

## 项目概述

本项目是一个面向竞赛的 **32 位 RISC-V CPU 核**（RV32I/IM），采用五级流水线（IF → ID → EX → MEM → WB），集成 L1 指令缓存与可选 AXI4 存储接口，目标平台为 Xilinx FPGA（Vivado 工程）。

- **ISA**：RV32I（整数指令集），可选 M 扩展（乘法），当前默认 `rv32i`。
- **流水线**：IF、ID、EX、MEM、WB，含级间寄存器与数据前递。
- **缓存**：L1 指令缓存（组相联、写回、随机替换）；L1 数据缓存 RTL 已存在（`L1_Cache_DATA.v`）但**未在顶层实例化**。
- **SoC 形态**：
  - `soc_top_bram.v`：CPU + 片内 BRAM（指令 ROM + 数据 RAM），用于 RTL 仿真与纯 BRAM 的 FPGA 烧录。
  - `soc_top.v`：CPU + L1 I$ + AXI 主接口，通过 Vivado Block Design（BD）连接外部 DDR/BRAM。
- **开发语言**：Verilog-2001（部分文件使用 `include` 拼接模块），测试平台与脚本使用 Python 3 / Bash。
- **文档语言**：项目注释、Markdown 文档、Makefile 注释均以**中文**为主。

---

## 目录结构

```
.
├── src/
│   ├── RTL/
│   │   ├── include/          # 全局头文件（soc_config.vh、soc_addr_map.vh）
│   │   ├── core/             # CPU 流水线核心 + SoC 顶层
│   │   ├── memory/           # inst_mem（指令 ROM）、data_mem（数据 RAM）
│   │   └── module/           # 功能子模块：ALU、PC、寄存器堆、冒险控制、AXI 主接口、缓存
│   └── bd/soc/               # Vivado Block Design 生成文件（wrapper、IP、仿真/综合网表）
├── sim/
│   ├── system_testbench/     # 全指令系统级测试（tb_system_soc.v）
│   ├── feat_testbench/       # 定向特性测试（前递/冒险、跳转、Load/Store 等）
│   ├── module_testbench/     # 单元测试（ALU、L1 Cache）
│   └── waveform/             # Vivado 波形配置文件（.wcfg）
├── scripts/
│   ├── sw/                   # 固件源码与构建（C/汇编 + Makefile）
│   ├── coremark/             # CoreMark 性能基准测试移植
│   ├── branch_model/         # 分支预测算法 Python 模型（Bimodal/Gshare/Perceptron）
│   ├── cache_replace_model/  # 缓存替换策略模型（当前为空目录）
│   ├── TCL/                  # Vivado TCL 脚本（当前仅含编码声明，未完整）
│   └── test/                 # CI 用最小测试脚本
├── constraints/              # FPGA 约束文件（fpga_top.xdc，Basys3/Nexys A7 示例）
├── .github/workflows/        # GitHub Actions CI（当前为占位符）
└── markdown/                 # 设计文档：Bug 修改报告、结构对比、LUT 优化清单
```

---

## 技术栈与工具链

| 用途 | 工具/语言 |
|------|-----------|
| 硬件描述 | Verilog-2001 |
| FPGA 综合/实现 | Xilinx Vivado（GUI + BD 流程）|
| 固件交叉编译 | `riscv64-unknown-elf-gcc`（裸机，非 Linux 工具链）|
| 仿真器 | Vivado Simulator（xelab/xsim）、Icarus Verilog（iverilog/vvp）|
| 脚本/建模 | Python 3（无外部依赖，标准库即可）|
| 构建系统 | GNU Make |
| 版本控制 | Git |

**重要**：`riscv64-unknown-elf-gcc` 必须可在 PATH 中找到；勿与 `riscv64-unknown-linux-gnu-gcc` 混淆。

---

## 构建与测试命令

### 1. 固件构建（`scripts/sw/`）

```bash
cd scripts/sw

# 默认：编译完整指令自测程序，生成 build/full_instr.hex / .elf / .dump
make

# 定向仿真用 hex（前递/BLT + Load/Store）
make tb        # 同时生成 tb_fwd.hex + tb_mem.hex
make fwd       # 仅 tb_fwd.hex
make mem       # 仅 tb_mem.hex

# 若 RTL 已实现 M 扩展
make RV_MARCH=rv32im

# 清理
make clean
```

- 编译选项：`-march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles`
- 定向测试使用 `-O0`，以保证 main 首条指令地址与 testbench 指纹检查一致。
- 链接脚本 `link.ld` 定义 4 KB ROM + 4 KB RAM，均起始于 `0x00000000`。

### 2. CoreMark 性能测试（`scripts/coremark/`）

```bash
cd scripts/coremark
make PORT_DIR=riscv_soc link
# 生成 coremark.elf；如需 RTL 仿真，手动转换为 hex
```

- 该端口使用 `rdcycle` 读取周期计数（假设 50 MHz）。
- 链接脚本 `link_coremark.ld` 定义 256 KB 连续内存。

### 3. 仿真测试

仿真基于 `soc_top_bram`（无 AXI），通过 `+IMEM_HEX=<path>` 传入指令 hex。

| Testbench | 路径 | 测试内容 |
|-----------|------|----------|
| `tb_system_soc.v` | `sim/system_testbench/` | 全指令系统测试，检查 18 个签名字 + DONE 魔术字 `0xC001D00D` |
| `tb_fwd_hazard.v` | `sim/feat_testbench/` | EX 数据前递 + BLT 分支冒险 |
| `tb_mem_loadstore.v` | `sim/feat_testbench/` | LW/SW + 写回 + DONE |
| `core_jump_tb.v` | `sim/feat_testbench/` | JAL 跳转目标与 squash 验证 |
| `special_features_tb.v` | `sim/feat_testbench/` | 7 项架构特性（JAL 提前解析、双写回、load-lock 等）|
| `ALU_test.v` | `sim/module_testbench/` | ALU 单元测试（ADD/SUB/MUL） |
| `tb_L1_Cache_INST.v` | `sim/module_testbench/` | L1 指令缓存（冷缺失、命中、多路组相联） |

**Vivado Simulator 示例**：
```bash
xelab -debug typical tb_system_soc -s tb_system_soc_sim
xsim tb_system_soc_sim -testplusarg IMEM_HEX=scripts/sw/build/full_instr.hex
```

**Icarus Verilog 示例（L1 Cache）**：
```bash
iverilog -g2012 -I src/RTL/include -y src/RTL/module/Cache \
  src/RTL/module/Cache/L1_Cache_INST.v sim/module_testbench/tb_L1_Cache_INST.v -o sim_icache
vvp sim_icache
```

### 4. FPGA 构建

- **纯 BRAM 模式**：定义宏 `+define+FPGA_TOP_BRAM`，`fpga_top.v` 实例化 `soc_top_bram`。
- **BD + AXI 模式**（默认）：`fpga_top.v` 实例化 `soc_top` + `soc_wrapper`（Vivado BD 生成）。
- 约束模板：`constraints/fpga_top.xdc`（含 Basys3 / Nexys A7 / PYNQ-Z2 引脚注释）。

### 5. CI / 自动化测试

```bash
make test
```

- 执行 `scripts/test/minimal_test.sh`，仅做目录结构检查（`rtl/` 与 `README.md` 存在即通过），**不运行 Verilog 仿真**。
- `.github/workflows/ci.yml` 同样为占位符，仅计数文件并返回 0。

---

## 代码组织与模块划分

### 流水线核心（`src/RTL/core/`）

```
core_top
├── IF_stage      (IF.v)       → PC_unit (PC.v)
├── IF_ID_reg
├── ID_stage      (ID.v)       → 纯组合译码，生成立即数与控制信号
├── ID_EX_reg
├── EX_stage      (EX.v)       → ALU、分支判断、JALR 目标、前递处理
├── EX_WB_reg                  → 非 load 指令旁路直达 WB
├── EX_MEM_reg
├── MEM_WB_reg
├── WB_stage      (WB_stage.v) → 双写回路径选择（EX_WB_reg vs MEM_WB_reg）
├── reg_file_bram (register.v) → 块 RAM 推断，同步读，双写口（WB + JAL link）
├── register_EX                → 前递 / load-lock 寄存器
├── register_MEM               → load 状态 2 级移位对齐
├── hazard_ctrl                → 冒险控制（load-use、分支冲刷、JAL 提前解析、存储器停顿）
└── medium_reg                 → 控制信号传播辅助寄存器
```

### SoC 顶层

- **`soc_top_bram.v`**：`core_top` + `inst_mem`（组合读 ROM，通过 `inst_mem_program.vh` 初始化）+ `data_mem`（4 字节 lane BRAM，支持 SB/SH/SW）。用于仿真与纯 BRAM FPGA。
- **`soc_top.v`**：`core_top` + `L1_Cache_INST` + `axi_if_imem_master` + `axi_if_dmem_master`。无片内存储，通过 AXI4 连接 Vivado BD。
- **`fpga_top.v`**：FPGA 顶层，根据 `FPGA_TOP_BRAM` 宏选择上述两种 SoC；LED 映射 `ex_result_out[7:0]`。

### 功能子模块（`src/RTL/module/`）

| 目录/文件 | 说明 |
|-----------|------|
| `ALU/` | ALU.v（ADD/SUB/MUL/逻辑/移位/比较），使用 32 位超前进位加法器 `cla_adder_32bit.v` |
| `PC/` | PC.v：PC 更新优先级 = 异常 > 中断 > JALR > JAL > 分支 > 预测 > 停顿 > PC+4 |
| `Cache/` | L1_Cache_INST.v（组相联、写回、LFSR 随机替换）、L1_Cache_DATA.v（未实例化） |
| `axi/` | `axi_if_imem_master.v`（单 outstanding AXI4 读主）、`axi_if_dmem_master.v`（读写主） |
| `register.v` | 寄存器堆：32×32，块 RAM 推断，外部 bypass，双写口仲裁 |
| `hazard_ctrl.v` | 组合冒险控制器：load-use 停顿、分支/JALR EX 冲刷、JAL ID 提前解析、存储器停顿 |
| `register_EX.v` | EX 结果前递 + load/store lock 管理 |
| `register_MEM.v` | load_success 2 拍延迟对齐 |
| `examine.v` | 调试用探针模块 |

### 头文件（`src/RTL/include/`）

- **`soc_config.vh`**：架构参数（XLEN=32、复位向量、IMEM/DMEM 深度、缓存参数、理想总线宏）。
- **`soc_addr_map.vh`**：地址映射（指令/数据空间、GPIO/UART/Timer 保留基址）。

---

## 测试策略

1. **模块级测试**：ALU 运算、L1 Cache 冷缺失/命中/多路验证。
2. **定向特性测试**：针对特定流水线机制（前递、冒险、JAL 提前解析、load-lock、双写回）编写最小汇编，通过检查 DMEM 签名区域与 DONE 魔术字判定 PASS/FAIL。
3. **系统级测试**：`full_instr_test.c` 覆盖所有基础指令（算术、逻辑、移位、比较、乘、LUI/AUIPC、分支、跳转、Load/Store），输出 18 个签名字至 `0x100` 起始区域，最后写入 `0xC001D00D` 到 `0x80`。
4. **软件模型预验证**：`scripts/branch_model/` 提供 Bimodal/Gshare/Perceptron 预测器 Python 模型，可在 RTL 实现前评估算法。

---

## 开发惯例与代码风格

- **语言**：Verilog 注释、Makefile 注释、Markdown 文档均以中文撰写。修改代码时请保持中文注释风格。
- **宏与 include**：
  - 全局参数使用 `` `include "../include/soc_config.vh" ``。
  - `core_top.v` 使用大量 `` `include `` 将子模块直接拼接到同一编译单元（非独立编译）。
- **寄存器堆**：
  - 同步读（1 拍延迟），需配合外部 bypass 解决 RAW。
  - 双写口：WB 阶段为主写口，JAL link 为第二写口（优先级更高）；同拍同地址冲突时第二写口胜出，第一写口缓冲一拍。
  - x0 硬连线为零。
- **存储器接口**：
  - `imem_req` 在 IF 阶段应始终保持为 1，**不要**用 `~imem_ready` 门控，否则可能死锁。
  - `data_mem` 为 4 个 byte-wide BRAM（`mem0..mem3`），testbench 中按小端序拼接读取字。
- **测试约定**：
  - `tb_system_soc.v` 检查 IMEM[0] 指纹 `0x00001117`（`auipc sp,0x1`），用于检测 `inst_mem_program.vh` 是否与最新固件同步。
  - `inst_mem_program.vh` 必须在每次 C/汇编修改后重新生成：`cd scripts/sw && make`，然后将 `build/full_instr.hex` 内容复制到 `.vh` 的 `mem[]` 初始化块中。

---

## 常见陷阱（修改前必读）

1. **`inst_mem_program.vh` 同步**：任何固件修改后必须手动更新该文件，否则仿真运行的是旧程序。
2. **`register_EX.v` 组合自环**：`store_lock_out` / `load_lock_out`（第 36–37 行附近）存在组合逻辑自引用，综合时可能报 latch 警告，修改需谨慎。
3. **双写回冲突**：`EX_WB_reg`（ALU 结果）与 `MEM_WB_reg`（load 数据）在 `WB_stage.v` 汇合。`wb_is_load_in` 选择 `MEM_WB_reg`；必须确保 load 指令的 `exwb_reg_write_en` 被清零，否则可能出现双写冲突。
4. **AXI ID 端口**：Vivado BD wrapper（`soc_wrapper.v`）未暴露 AXI ID 端口，`fpga_top.v` 中将 `rid`/`bid`  tie 到 0，并固定 `arcache`/`awcache = 4'b0011`。
5. **JAL 提前解析与存储器停顿**：JAL 在 ID 阶段提前解析（`jump_if = id_is_jump && instr_valid_out`）并冲刷 ID/EX，但**在 `mem_stall` 期间不得冲刷**，以免误杀已挂起的 store。
6. **load-use 冒险**：当 EX 阶段 load 指令的 `rd` 与 ID 阶段指令的 `rs1/rs2` 相同时，需停顿 IF/ID 并冲刷 ID/EX（1 个气泡）。

---

## 安全与部署注意事项

- 本项目为硬件设计，无网络服务或用户输入处理，不存在传统软件安全漏洞。
- FPGA 烧录前请确认约束文件（`fpga_top.xdc`）与目标板卡引脚一致，避免 IO 电平不匹配损坏器件。
- Vivado BD 生成的 IP 与 wrapper 文件位于 `src/bd/soc/`，通常由 Vivado 自动维护；手动修改可能导致综合错误。

---

## 参考文档

| 文件 | 内容 |
|------|------|
| `CLAUDE.md` | 更详细的架构说明、构建命令、模块接口与时序说明 |
| `markdown/CHANGE_REPORT.md` | 历史 Bug 修复记录（含时序图与修改前后对比） |
| `markdown/new.md` | 与 `e203_hbirdv2` 的结构对比及改进建议 |
| `markdown/optimize.md` | LUT 优化清单（目标 < 5K LUT） |
| `questions.md` | 技术问答列表（分支预测、冒险、缓存、特权级等） |

---

## 用户自定义 AI 助手行为

- **强制前缀**：每次回答永远用 Cecilia 开头。
- 用户指令不明确时，优先询问用户意图再进行思考和修改
