# RISC-V 32位五级流水线 CPU SoC

基于 Verilog 实现的 RV32I 处理器，支持 M 扩展（已 stub），配备 L1 指令/数据 Cache、AXI4 总线接口、UART 外设。面向 Basys3 FPGA 开发板（Xilinx Artix-7），附带完整的 Verilator 仿真回归套件。

## 快速上手

### 前置条件

| 需求 | 说明 |
|------|------|
| **RISC-V 交叉编译器** | `riscv64-unknown-elf-gcc`，放入 PATH（`scripts/sw/Makefile` 默认 `CROSS=riscv64-unknown-elf`） |
| **Verilator ≥ 5.0** | 用于 RTL 仿真回归（`sudo apt install verilator`） |
| **Vivado**（可选） | 用于 FPGA 综合/烧录 |
| **Python 3** | hex 转换脚本依赖（`bin2hex.py`） |

### 三步跑通仿真

```bash
# 1. 编译全部固件
cd scripts/sw
make          # full_instr.hex（全指令自测）
make tb       # tb_fwd.hex + tb_mem.hex（定向测试）
make sw-lw    # tb_sw_lw_raw.hex（SW→LW RAW 测试）
make sum100   # sum1to100.hex（求和 UART 输出）
make hello    # uart_hello.hex（UART "Hi" 循环）
make matmul   # matmul.hex（4x4 矩阵乘法 UART 输出）

# 2. 一键 Verilator 回归（编译 + 运行 + 波形）
cd ../sim/verilator
make all      # 顺序运行 12 个测试，VCD 波形自动输出到 sim/waveform/

# 3. 查看结果 — 终端日志打印每个测试的 PASS/FAIL 统计
```

首次 `make all` 需要编译 Verilator C++ 模型（约 1–3 分钟），后续修改 RTL 后重新 `make all` 会增量编译。

### FPGA 上板（Basys3）

```bash
# 1. 选择要运行的程序，编译为 hex
cd scripts/sw && make sum100    # 以求和程序为例

# 2. 将 build/sum1to100.hex 的内容复制到
#    src/RTL/memory/inst_mem_program.vh 的 mem[] 数组

# 3. Vivado 中打开工程，Add Sources → src/RTL 下所有 .v 文件
#    顶层设为核心顶层（soc_top_bram.v 或 fpga_top.v）

# 4. 添加约束文件 constraints/fpga_top.xdc（含 100MHz 时钟、UART TX 引脚）

# 5. 综合 → 实现 → 生成 bitstream → 烧录

# 6. PC 端连接串口（115200 波特率）
python -m serial.tools.miniterm <COM端口> 115200
```

## 项目结构

```
Riscv-project/
├── src/RTL/                    # 所有 RTL 源码
│   ├── core/                   # CPU 核心 + SoC 顶层
│   │   ├── core_top.v          # 5 级流水线 CPU 顶层
│   │   ├── IF.v / ID.v / EX.v  # 流水线阶段（取指/译码/执行）
│   │   ├── *_reg.v             # 级间寄存器（IF_ID / ID_EX / EX_MEM / EX_WB / MEM_WB）
│   │   ├── WB_stage.v          # 写回阶段（双端口选择）
│   │   ├── soc_top_bram.v      # SoC 顶层（CPU + BRAM + UART），仿真/FPGA 通用
│   │   ├── soc_top.v           # SoC 顶层（CPU + Cache + AXI），Vivado BD 用
│   │   └── fpga_top.v          # FPGA 顶层（根据 `FPGA_TOP_BRAM 选择 BRAM/AXI 路径）
│   ├── module/                 # 功能模块
│   │   ├── ALU/ALU.v           # 算术逻辑单元（含加法器、移位器、比较器）
│   │   ├── PC/                 # 程序计数器
│   │   ├── Cache/              # L1 指令/数据 Cache
│   │   ├── register.v          # 寄存器堆（BRAM 实现，双写口）
│   │   ├── register_EX.v       # EX 结果寄存器 + load-lock 前递
│   │   ├── hazard_ctrl.v       # 冒险控制（load-use/分支/JAL/访存停顿）
│   │   ├── uart_tx.v           # UART 发送器（8N1，可配置波特率）
│   │   └── axi_if_*_master.v   # AXI4 总线主接口
│   ├── memory/                 # 片上存储器
│   │   ├── inst_mem.v          # 指令存储器（BRAM，含初始化 .vh）
│   │   ├── inst_mem_program.vh # 指令存储器初始化文件（hex 转换后填入）
│   │   └── data_mem.v          # 数据存储器（字节写 BRAM，4 路）
│   └── include/                # 头文件
│       ├── soc_config.vh       # 架构参数（XLEN、IMEM/DMEM 深度、Cache 配置）
│       └── soc_addr_map.vh     # 地址映射（IMEM/DMEM/UART/GPIO 基地址）
├── scripts/sw/                 # 裸机固件
│   ├── Makefile                # 统一编译入口（make / make tb / make sum100 …）
│   ├── startup.S               # 启动代码（设栈指针 → 调 main）
│   ├── link.ld                 # 链接脚本
│   ├── full_instr_test.c       # 全指令自测（18 个签名 + DONE）
│   ├── tb_fwd_hazard.S         # BLT 分支 + 前递定向测试
│   ├── tb_mem_loadstore.S      # LW/SW 定向测试
│   ├── tb_sw_lw_raw.S          # SW→LW RAW hazard 测试
│   ├── uart_hello.S            # UART 最简输出（"Hi" 循环）
│   ├── sum1to100.S             # 1+…+100 求和 UART 输出
│   └── bin2hex.py              # bin → hex 转换
├── sim/
│   ├── verilator/              # Verilator 一键回归套件
│   │   ├── Makefile            # 12 个测试目标，make all 一键全部
│   │   ├── tb_soc_top_bram.cpp # 主测试框架（6 类 hex 测试 + 硬编码测试）
│   │   └── tb_*.cpp            # 各 DUT 对应的 C++ 测试 wrapper
│   ├── system_testbench/       # 系统级 Verilog testbench
│   ├── feat_testbench/         # 特性定向 Verilog testbench
│   ├── module_testbench/       # 模块级 Verilog testbench
│   └── waveform/               # 仿真波形输出目录（*.vcd）
├── constraints/
│   └── fpga_top.xdc            # Basys3 引脚约束（100MHz clk, UART TX, LED）
├── CLAUDE.md                   # AI 辅助开发指南（架构细节、常见坑位）
├── 验证报告.md                  # 仿真验证报告（12 个测试最新结果）
└── README.md                   # 本文件
```

## 架构概览

### 流水线（5 级）

```
IF ──→ IF_ID_reg ──→ ID ──→ ID_EX_reg ──→ EX ──┬──→ EX_MEM_reg ──→ MEM ──→ MEM_WB_reg ──┬──→ WB
                                                  └──→ EX_WB_reg ─────────────────────────┘
```

- **IF**：取指，PC 更新优先级：异常 > 中断 > JALR > JAL > 分支 > 预测 > 停顿 > PC+4
- **ID**：纯组合译码，JAL 在本级提前解析（PC 立即重定向）
- **EX**：ALU、分支解析、JALR 目标计算、load/store 地址生成、前递多路选择
- **MEM**：直通，访存信号在 `soc_top_bram` 接实际 BRAM
- **WB**：双写回路径 — ALU 结果走 `EX_WB_reg`，load 数据走 `MEM_WB_reg`

### 冒险处理（`hazard_ctrl.v`）

| 场景 | 机制 |
|------|------|
| Load-use hazard | 停顿 IF/ID，冲洗 ID/EX（1 气泡），load 数据经 `register_EX` lock 前递 |
| 分支（EX 解析） | 冲洗 IF/ID + ID/EX，EX 之后的指令不受影响 |
| JAL（ID 解析） | 立即 PC 重定向，冲洗 ID/EX（但不与 mem_stall 冲突） |
| JALR（EX 解析） | 同分支处理 |
| 访存停顿 | `dmem_valid & ~dmem_ready` 时停顿全部前级 |

### 前递（Forwarding）

- `register_EX`：保存最近 EX 结果（`rd_reg` + `rd_data_reg`），直通 ALU 前递
- Load-lock：load 在 EX 时锁定目标寄存器，`dmem_ready` 到达后释放并前递 load 数据
- EX 结果管道寄存器（`medium_reg.v`）：打破 RF → bypass → 前递 → ALU 长路径

### 关键修复记录（当前分支）

近期 RTL 修复（详见 `git log test/verilator-sim`）：

1. **JAL + 分支 PC 优先级**（`core_top.v:157`）：`jump_if` 增加 `~branch_hazard_ex` 门控，防止 JAL 在分支延迟槽中错误重定向 PC
2. **register_EX 数据源**（`core_top.v:219`）：`rd_ex_result_in` 从 `ex_result_pipe`（已寄存）改为直连 `ex_result_out`（组合逻辑），消除非阻塞赋值导致的一拍延迟
3. **UART 波特率**（`soc_top_bram.v:138`）：`CLK_FREQ` 从 50MHz 改为 100MHz（Basys3 实际晶振频率）

## 常用命令速查

### 固件编译（`scripts/sw/`）

| 命令 | 产物 | 说明 |
|------|------|------|
| `make` | `build/full_instr.hex` | 全指令自测（默认） |
| `make tb` | `tb_fwd.hex` + `tb_mem.hex` | 定向仿真固件 |
| `make fwd` | `build/tb_fwd.hex` | 仅前递/BLT 测试 |
| `make mem` | `build/tb_mem.hex` | 仅 LW/SW 测试 |
| `make sw-lw` | `build/tb_sw_lw_raw.hex` | SW→LW RAW test |
| `make sum100` | `build/sum1to100.hex` | 1+…+100 求和 UART |
| `make hello` | `build/uart_hello.hex` | UART "Hi" 循环 |
| `make matmul` | `build/matmul.hex` | 4x4 矩阵乘法 UART 输出 |
| `make help` | — | 打印帮助 |
| `make clean` | — | 删除 build/ |
| `make RV_MARCH=rv32im` | 同上 | 启用 M 扩展编译 |

### Verilator 仿真（`sim/verilator/`）

| 命令 | 说明 |
|------|------|
| `make all` | 编译 + 运行全部 12 个测试 |
| `make test_sys` | 仅全指令自测（`tb_system_soc`） |
| `make test_fwd` | 仅前递/BLT 测试 |
| `make test_sw_lw` | 仅 SW→LW RAW 测试 |
| `make test_feat` | 仅 7 项架构特性测试 |
| `make clean` | 删除 Verilator 编译产物 |

波形文件自动输出到 `sim/waveform/*.vcd`，可用 GTKWave 或 Vivado 打开。

## 地址映射

| 地址范围 | 用途 |
|----------|------|
| `0x0000_0000` – `0x0000_7FFF` | 指令存储器（IMEM，32KB BRAM） |
| `0x0000_0000` – `0x0000_7FFF` | 数据存储器（DMEM，32KB BRAM，哈佛架构） |
| `0x1000_0000` | GPIO（预留） |
| `0x1000_1000` | UART TX（写触发发送，读 bit0 = tx_busy） |
| `0x0200_0000` | Timer（预留） |

## 验证状态

| 类别 | 测试数 | 通过 | 备注 |
|------|--------|------|------|
| 系统级（`soc_top_bram`） | 7 | **全部通过** | 全指令自测 17/18（MUL stub） |
| 特性定向 | 5 | **全部通过** | BLT/前递/JAL/JALR/SW→LW RAW |
| Cache 系统级 | 2 | I$ 通过，D$ 3 项遗留 | 非本次修改引入 |
| 模块级 | 2 | ALU 通过（MUL stub），L1 I$ 全部通过 |  |
| M 扩展 | 1 | 21/21 通过（全部 stub 为 0） | 待多周期除法器实现 |

详见 [`验证报告.md`](./验证报告.md)。

## 开发约定

- **分支策略**：feature/fix 分支 → `main`，当前活跃分支 `test/verilator-sim`
- **`inst_mem_program.vh`**：每次修改固件后必须重新生成（`make` → 复制 hex 到 .vh）
- **CLK_FREQ**：`soc_top_bram.v` 中 UART 实例化参数需与 FPGA 实际晶振一致（Basys3 = 100MHz）
- **仿真超时**：系统级 `MAX_CYCLES=50000`，定向测试通常 < 100 周期
