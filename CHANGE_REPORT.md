# Change Report — fix/load-store-lock

## 概述

修复 RISC-V CPU 核心中 load/store 锁机制的多个关键 Bug。共涉及 6 个 Bug 的修复，覆盖 store 地址异常、ALU 前递污染、DONE 检测时序、stale ready 跳过、load 结果前递注入、以及 load-use 冒险检测窗口问题。`tb_mem_loadstore` 和 `special_features_tb` 均由 FAIL 变为 PASS。

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

## Bug 4: Stale dmem_ready 导致 load FSM 卡在 L_BUSY（data_mem.v + register_EX.v）

**现象**：在 `tb_mem_loadstore` 中，SW 到 0x200 后紧跟 LW（0x200），load 结果始终为 0x00000200（地址）而非期望的 0x11223344（数据）。

**根因**：data_mem 的 registered read 特性导致两个问题交织：
1. **data_mem 数据被覆盖**：`mem_data`（读数据寄存器）每个周期无条件更新。LW 完成读取后，下一周期 `dmem_valid=0`，但 `word_addr` 已被尚未完成译码的指令地址驱动，`mem_data` 被覆写为其他地址的内容。
2. **Stale ready 跳过机制不完整**：store 完成后 `dmem_ready` 仍高，紧接的 LW 进入 EX/MEM 时误认 ready。FSM 通过 `dmem_ready_d1` 检测到 stale ready 并正确跳过（`first_cycle_in_busy` 清零），但 `load_success` 不再置起（load 已流出 EX/MEM），FSM 永远无法从 L_BUSY 进入 L_RELEASE。

**修复**：
- `data_mem.v`：`mem_data`/`size_q`/`position_q` 仅在 `valid && read_en` 时更新，防止无关地址污染读数据
- `register_EX.v`：在 L_BUSY 状态增加第三条退出路径——`!first_cycle_in_busy && dmem_ready && !load_success`，跳过 stale 后由真实 dmem_ready 触发状态转移

**文件**：`src/RTL/memory/data_mem.v:69-74`, `src/RTL/module/register_EX.v:75-78`

---

## Bug 5: L_RELEASE 期间 load 结果未注入 ALU 前递链（register_EX.v）

**现象**：`SIG[17]` 正确读取 0x11223344（Bug 4 修复后），但紧随 LW 之后的 SW 写入地址仍为 0x00000200 而非数据 0x11223344。

**根因**：load 完成进入 L_RELEASE 后，load 结果仅通过 `rd_data_load_out` 前递。但 ALU 前递链（`rd_reg`/`rd_data_reg`）未被更新，EX 中的指令通过 ALU 前递读取到 1 拍前的旧值（地址 0x200）。

**修复**：在 L_RELEASE 状态将 `rd_reg_load`/`rd_data_load_saved` 推入 ALU 前递链：
```verilog
end else if (lstate == L_RELEASE) begin
    rd_reg2 <= rd_reg;              rd_data_reg2 <= rd_data_reg;
    rd_reg  <= rd_reg_load;         rd_data_reg  <= rd_data_load_saved;
end
```

**文件**：`src/RTL/module/register_EX.v:145-148`

---

## Bug 6: Load-use 冒险检测窗口过窄（register_EX.v + hazard_ctrl.v）

**现象**：`special_features_tb` T3 load-use 测试中 `x3=0x01`（应为 `0x65 = 101`）。LW 后紧跟 ADD，load-use 冒险未被检测到，导致 ADD 在 ID 阶段未被正确停顿。

**根因**：`load_pending` 仅在 lstate==L_BUSY 时置起，但 load 进入 EX 的首个周期 lstate 仍为 L_IDLE（load_enable=1 后下一拍才进 L_BUSY）。因此 ID 段的 ADD 看到 `load_pending=0`，load-use 冒险检测条件不满足。

**修复**：
- `register_EX.v`：`rd_reg_load_out` 和 `load_pending` 在 `lstate==L_IDLE && load_enable` 时组合逻辑提前暴露，使 hazard_ctrl 在 load 进入 EX 的第 1 拍就能检测到冒险
- `hazard_ctrl.v`：flush_idex 中 `load_use_hazard` 用 `~stall_back` 门控，防止 mem_stall 期间 flush 杀死卡在 EX 中的 load 自身

**文件**：`src/RTL/module/register_EX.v:194,200`, `src/RTL/module/hazard_ctrl.v:59-62`

**现象**：测试 while 循环超时，未检测到 DONE 写入。

**根因**：`dmem_ready` 比 `dmem_valid` 滞后 1 个周期。对于最后的单周期 store（到 0x80），`dmem_valid && dmem_wen` 出现时 `dmem_ready=0`，且 store 仅在 EX/MEM 停留 1 拍（下一条指令 `j .` 无访存），导致连续检测条件无法满足。

**修复**：将 DONE 检测从连续组合逻辑改为锁存器 `tb_done_hit`，posedge 捕捉后保持。

**文件**：`sim/feat_testbench/tb_mem_loadstore.v:111-119`

---

## 影响范围

| 模块 | 变更类型 | 风险 |
|------|----------|------|
| `EX.v` | 添加 1 条 wire 声明 | 低 |
| `register_EX.v` | ALU 前递门控 + load/store FSM 重写 + 早期冒险暴露 | 中 |
| `hazard_ctrl.v` | flush_idex 门控条件调整 | 低 |
| `data_mem.v` | mem_data 更新门控 | 低 |
| `core_top.v` | 端口连接更新 | 低 |
| `tb_mem_loadstore.v` | 测试用例新增 | 无 |

## 回归测试

| 测试 | 结果 |
|------|------|
| tb_mem_loadstore | PASS |
| tb_mem_loadstore_debug | PASS |
| tb_jump_no_mem | PASS |
| core_jump_tb | PASS |
| special_features_tb | **22/22 ALL PASS**（T3 load-use 已修复）|
| tb_fwd_hazard | FAIL（已有问题：hex 加载，需 riscv64-unknown-elf-gcc） |
