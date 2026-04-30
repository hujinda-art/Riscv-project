# Change Report — fix/load-store-lock

## 概述

修复 RISC-V CPU 核心中 load/store 锁机制的三个关键 Bug，涉及 store 地址异常、ALU 前递污染、以及 DONE 检测时序问题。`tb_mem_loadstore` 测试由 FAIL 变为 PASS。

---

## Bug 1: store 地址始终为 0（EX.v）

**现象**：SW 指令写入地址始终为 0x00000000，而非正确的目标地址（0x200、0x144、0x80）。

**根因**：`mem_addr` 在 `EX.v` 中未显式声明，作为隐式 Verilog wire，iverilog 推断宽度不正确，被多个源驱动时结果恒为 0。

**修复**：在 `assign` 之前添加 `wire [31:0] mem_addr;` 显式声明。

**文件**：`src/RTL/core/EX.v:158`

---

## Bug 2: ALU 前递寄存器被非写寄存器指令污染（register_EX.v）

**现象**：SIG[17] 读取值为 0，而非期望的 0x11223344。原因：LW 依赖于前一条指令（`li a5, 0xC001D00D`）的转发结果，但中间的 SW 指令（rd=x0）将 ALU 前递寄存器覆盖为 x0=0，导致 rs1_data_final 获取错误数据。

**根因**：`register_EX.v` 中的 ALU 前递移位寄存器对所有指令无条件更新，包括 `reg_write_en=0` 的 store/branch 等指令。

**修复**：
- 添加 `reg_write_en` 输入端口
- 将 ALU 前递更新条件改为 `!load_enable && reg_write_en`
- 确保只有真正写寄存器的 ALU 指令（R/I/JALR/LUI/AUIPC 型）才会推进前递链

**文件**：`src/RTL/module/register_EX.v:117-135`, `src/RTL/core/core_top.v:199`

---

## Bug 3: DONE 检测时序竞争（tb_mem_loadstore.v）

**现象**：测试 while 循环超时，未检测到 DONE 写入。

**根因**：`dmem_ready` 比 `dmem_valid` 滞后 1 个周期。对于最后的单周期 store（到 0x80），`dmem_valid && dmem_wen` 出现时 `dmem_ready=0`，且 store 仅在 EX/MEM 停留 1 拍（下一条指令 `j .` 无访存），导致连续检测条件无法满足。

**修复**：将 DONE 检测从连续组合逻辑改为锁存器 `tb_done_hit`，posedge 捕捉后保持。

**文件**：`sim/feat_testbench/tb_mem_loadstore.v:111-119`

---

## 影响范围

| 模块 | 变更类型 | 风险 |
|------|----------|------|
| `EX.v` | 添加 1 条 wire 声明 | 低 |
| `register_EX.v` | ALU 前递门控 + load/store FSM 重写 | 中 |
| `core_top.v` | 端口连接更新 | 低 |
| `tb_mem_loadstore.v` | 测试用例新增 | 无 |

## 回归测试

| 测试 | 结果 |
|------|------|
| tb_mem_loadstore | PASS |
| tb_mem_loadstore_debug | PASS |
| tb_jump_no_mem | PASS |
| core_jump_tb | PASS |
| special_features_tb | 21/22 PASS（1 项已有失败：T3 load-use）|
| tb_fwd_hazard | FAIL（已有问题：hex 加载） |
