# 逻辑 Bug 修改报告

日期：2026-04-09  
涉及文件：`src/RTL/core/EX.v`、`src/RTL/module/register_EX.v`、`src/RTL/core/core_top.v`

---

## Bug 1 — `load_success` 信号接法错误，load 锁机制整体失效

**文件**：`src/RTL/core/core_top.v` 第 175-181 行

### 问题描述

`register_MEM` 模块内部用 2 级移位链对 `load_success` 做延迟，目的是对齐同步读存储器（`data_mem`）的 1 拍流水延迟，在正确的时钟周期输出 `load_status_out = 1`，从而通知 `register_EX` 清除 load 锁、切换前递数据来源。

原代码把 `load_success` 接为无条件的 `dmem_rvalid`。而在 `soc_top.v` 中 `dmem_rvalid = 1'b1` 恒为高，导致移位链在复位后 2 拍即永久输出 `load_status_out = 1`。结果是：

- `load_lock` 在 load 指令进入 EX 的同一拍内就会被清除（无法起到锁定作用）。
- `rd_data_in_final` 始终选择 `dmem_rdata`，对所有指令（包括非 load）的前递数据均造成污染。

### 修改

```verilog
// 修改前
.load_success(dmem_rvalid),

// 修改后
.load_success(dmem_rvalid & exmem_mem_read_en_out),
```

### 时序对照（理想同步存储器，rvalid 恒 1）

| 周期 | 事件 |
|------|------|
| N    | load 在 EX 阶段，`ex_is_load=1`，`load_lock` 置 1 |
| N+1  | load 进入 EX/MEM，`exmem_mem_read_en_out=1`，存储器锁存地址，`load_success=1` → `load_status_1=1` |
| N+2  | `load_status_2=1` → `load_status_out=1`，同拍 `dmem_rdata` 有效，`load_lock` 清 0，前递切换到读出数据 |

---

## Bug 2 — `ex_reg_write_en` 遗漏 LUI / AUIPC，算了但不写回

**文件**：`src/RTL/core/EX.v` 第 75-76 行

### 问题描述

`ID_stage` 的 `reg_write_en` 信号已将 LUI / AUIPC 纳入"可写回"集合，并在 `EX_stage` 中专门计算了这两条指令的 `ex_result`（`ex_imm` 与 `ex_pc + ex_imm`）。但 `EX_stage` 自己产生的 `ex_reg_write_en` 仅放行 R/I/JALR 三类，LUI / AUIPC 的结果永远不会被写入寄存器堆。

### 修改

```verilog
// 修改前
assign ex_reg_write_en = instr_valid_final &
    ((ex_opcode == OPCODE_R_TYPE) || (ex_opcode == OPCODE_I_TYPE) || (ex_opcode == OPCODE_JALR));

// 修改后
assign ex_reg_write_en = instr_valid_final &
    ((ex_opcode == OPCODE_R_TYPE) || (ex_opcode == OPCODE_I_TYPE) ||
     (ex_opcode == OPCODE_JALR)   || (ex_opcode == OPCODE_LUI)   ||
     (ex_opcode == OPCODE_AUIPC));
```

---

## Bug 3 — 前递比较未屏蔽 x0，会污染以 x0 为源的操作数

**文件**：`src/RTL/core/EX.v` 第 135-141 行

### 问题描述

`rs1_data_final` / `rs2_data_final` 的选择逻辑直接用 `forward_rd_in == ex_rs1` 进行匹配。若上一条指令的目的寄存器号恰好为 0（或处于初始态 0），而当前指令也使用 `x0` 作为源寄存器，则会误命中前递条件，将上一条指令的非零计算结果前递给 `x0`，与寄存器堆中 `x0` 恒为 0 的设计矛盾。

### 修改

```verilog
// 修改前
assign rs1_data_final = (!forward_load_lock_in && (forward_rd_reg_load_in == ex_rs1)) ?
    forward_rd_data_reg_load_in : (forward_rd_in == ex_rs1) ?
    forward_rd_data_in : rs1_data;

assign rs2_data_final = (!forward_load_lock_in && (forward_rd_reg_load_in == ex_rs2)) ?
    forward_rd_data_reg_load_in : (forward_rd_in == ex_rs2) ?
    forward_rd_data_in : rs2_data;

// 修改后
assign rs1_data_final =
    (!forward_load_lock_in && (forward_rd_reg_load_in != 5'b0) && (forward_rd_reg_load_in == ex_rs1)) ?
        forward_rd_data_reg_load_in :
    ((forward_rd_in != 5'b0) && (forward_rd_in == ex_rs1)) ?
        forward_rd_data_in :
        rs1_data;

assign rs2_data_final =
    (!forward_load_lock_in && (forward_rd_reg_load_in != 5'b0) && (forward_rd_reg_load_in == ex_rs2)) ?
        forward_rd_data_reg_load_in :
    ((forward_rd_in != 5'b0) && (forward_rd_in == ex_rs2)) ?
        forward_rd_data_in :
        rs2_data;
```

---

## Bug 4 — JALR 的 `ex_result` 写入跳转目标地址而非 PC+4

**文件**：`src/RTL/core/EX.v` 第 161 行

### 问题描述

RISC-V 规范要求 JALR 将 `PC+4` 写入链接寄存器 `rd`，跳转目标（`(rs1+imm) & ~1`）只影响 PC。

现有代码将 `pc_jalr`（跳转目标）赋给 `ex_result`，导致 `rd` 中存入目标地址而非返回地址，调用返回逻辑会出错。本设计已有 `JAL` 在 IF/ID 阶段提前写回 `PC+4` 的机制，JALR 应保持一致，写回 `ex_pc_plus4`。

### 修改

```verilog
// 修改前
(ex_opcode == OPCODE_JALR) ? pc_jalr :

// 修改后
(ex_opcode == OPCODE_JALR) ? ex_pc_plus4 :
```

---

## Bug 5 — `register_EX` 的 `load_lock` 和 `rd_reg_load` 块不响应 flush，冲刷后状态不一致

**文件**：`src/RTL/module/register_EX.v` 第 31-53 行

### 问题描述

`register_EX` 内有三个 always 块：

| 块 | 管理信号 | 原本是否响应 flush |
|----|----------|--------------------|
| 块 A | `rd_reg` / `rd_data_reg`（正常前递） | ✅ 响应 |
| 块 B | `load_lock` | ❌ 不响应 |
| 块 C | `rd_reg_load` / `rd_data_reg_load`（load 前递） | ❌ 不响应 |

当 branch/jalr 触发 `flush_idex` 冲刷时，块 A 清零，块 B/C 保持旧状态。下一条新取指令进 EX 时，`load_lock` 可能还是 1，`rd_reg_load` 中仍是被冲刷指令的寄存器号，导致错误前递或指令无效。

### 修改

**块 B（load_lock）**：

```verilog
// 修改前
if (!rst_n) begin
    load_lock <= 1'b0;
end else if (load_success) begin

// 修改后
if (!rst_n) begin
    load_lock <= 1'b0;
end else if (flush) begin
    load_lock <= 1'b0;
end else if (load_success) begin
```

**块 C（rd_reg_load / rd_data_reg_load）**：

```verilog
// 修改前
if (!rst_n) begin
    rd_reg_load <= NOP_REG;
    rd_data_reg_load <= NOP_DATA;
end else if (load_success || load_enable) begin

// 修改后
if (!rst_n) begin
    rd_reg_load <= NOP_REG;
    rd_data_reg_load <= NOP_DATA;
end else if (flush) begin
    rd_reg_load <= NOP_REG;
    rd_data_reg_load <= NOP_DATA;
end else if (load_success || load_enable) begin
```

---

## Bug 6 — 后半段流水寄存器 flush 被硬编码为 0，外部 flush 无法清空整条流水线

**文件**：`src/RTL/core/core_top.v` 第 329、353、387 行

### 问题描述

`EX_WB_reg`、`EX_MEM_reg`、`MEM_WB_reg` 的 `flush` 端口在实例化时均被接为 `1'b0`。顶层的外部 `flush` 信号（用于异常/中断复位等场景）只能清空前半段（IF/ID、ID/EX），后半段三个寄存器保持旧状态继续提交，会造成写错误地址或读出旧数据。

注意：branch/jalr 引起的 `branch_hazard_ex` 不在此修复范围——这类冲刷只需清前半段，后半段已在正确执行路径上，不应冲刷。本次只将外部 `flush` 接通到后半段。

### 修改

```verilog
// 修改前（三处 1'b0）
EX_WB_reg  u_ex_wb  (...  .flush(1'b0), ...);
EX_MEM_reg u_exmem  (...  .flush(1'b0), ...);
MEM_WB_reg u_memwb  (...  .flush(1'b0), ...);

// 修改后
EX_WB_reg  u_ex_wb  (...  .flush(flush), ...);
EX_MEM_reg u_exmem  (...  .flush(flush), ...);
MEM_WB_reg u_memwb  (...  .flush(flush), ...);
```

---

## 改动文件汇总

| 文件 | 改动数 | 对应 Bug |
|------|--------|----------|
| `src/RTL/core/EX.v` | 3 处 | Bug 2、Bug 3、Bug 4 |
| `src/RTL/module/register_EX.v` | 2 处 | Bug 5 |
| `src/RTL/core/core_top.v` | 4 处 | Bug 1、Bug 6 |

---

## 第二轮修复（仿真 T3 失败触发）

仿真结果显示 T3（load-use 前递）`x3=1`（期望 101），说明 LW 写回成功但前递失效。
根因为三层嵌套 Bug，须同时修复才能让 load-use 前递正确工作。

---

### Bug 7：`register_EX` 在 load-use 停顿时被错误冲刷

**文件**：`src/RTL/core/core_top.v`

**问题**：`flush_idex = flush | branch_hazard_ex | load_use_hazard`，  
`register_EX.flush` 接的是 `flush_idex`。当 load-use 停顿发生时 `flush_idex=1`，  
register_EX 把 `rd_reg_load`（正确的目的寄存器 x2）清为 x0，前递状态被摧毁。  

**修复**：register_EX 的 flush 改为只响应真正的流水线冲刷，排除 load-use 停顿。

```verilog
// 旧
.flush(flush_idex),

// 新
.flush(flush | branch_hazard_ex),
```

---

### Bug 8：`register_EX.load_success` 经过 2 拍延迟，与 1 拍停顿时序错位

**文件**：`src/RTL/core/core_top.v`

**问题**：`register_EX.load_success` 连接的是 `register_MEM` 的 `load_status_out`（2 级移位链输出）。  
时序分析：
- 停顿 1 拍（load_use_hazard）后，依赖指令在 LW 进入 EX/MEM 后的第 **1** 拍进入 EX。
- `load_status_out` 要再过 **2** 拍才变 1（移位链延迟）。
- 结果：依赖指令在 EX 时 `load_lock` 仍为 1，前递条件 `!load_lock` 不满足，读到寄存器堆旧值 0。

**修复**：load_success 直接使用 EX/MEM 阶段的握手信号，同时移除不再需要的 `register_MEM` 实例。

```verilog
// 旧
wire load_status_out;
register_MEM u_register_mem (
    .flush(flush_idex),
    .load_success(dmem_rvalid & exmem_mem_read_en_out),
    .load_status_out(load_status_out)
);
register_EX u_register_ex (..., .load_success(load_status_out), ...);

// 新（register_MEM 实例已删除）
register_EX u_register_ex (..., .load_success(dmem_rvalid & exmem_mem_read_en_out), ...);
```

---

### Bug 9：`rd_reg_load` 在 `load_success` 时被 NOP 的 x0 覆盖

**文件**：`src/RTL/module/register_EX.v`

**问题**：原代码把 `load_success` 和 `load_enable` 合并在同一分支：

```verilog
// 旧
end else if (load_success || load_enable) begin
    rd_reg_load <= rd_in;           // load_success 时 rd_in = NOP 的 rd = x0
    rd_data_reg_load <= rd_data_in_final;
end
```

`load_success=1` 时，流水线 EX 位置是气泡（NOP），`rd_in = x0`。  
于是目的寄存器从正确的 x2 被覆盖为 x0，前递判断 `rd_reg_load != 0` 失败。  
同时移除了 `rd_data_in_final` 中间线，ALU 前递通道改为直接使用 `rd_ex_result_in`。

**修复**：拆分两个分支，`load_success` 时只更新数据，保留目的寄存器。

```verilog
// 新
end else if (load_success) begin
    rd_data_reg_load <= rd_mem_rdata_in;   // 只更新数据，保留 rd_reg_load
end else if (load_enable) begin
    rd_reg_load      <= rd_in;             // 锁存目的寄存器
    rd_data_reg_load <= rd_ex_result_in;   // 暂存 EX 结果（地址），待替换
end
```

ALU 前递通道（`rd_reg/rd_data_reg`）同步修改，去掉与 load 数据的耦合：

```verilog
// 旧
rd_data_reg <= rd_data_in_final;   // 可能混入 load 数据

// 新
rd_data_reg <= rd_ex_result_in;    // 始终使用 EX 结果
```

---

### 三个 Bug 的时序关联图

```
Cycle K  : LW 在 EX          → load_enable=1 → rd_reg_load=x2, load_lock=1
                                load_use_hazard=1 → stall, flush_idex=1
Cycle K+1: LW 在 EX/MEM      → load_success(直接)=1
                                addi x3 滞留 IF/ID
Cycle K+2: LW 在 MEM/WB      → 数据就绪(data_out=100)
           NOP 在 EX          → posedge K+2 采样: load_success=1
                                  load_lock←0, rd_data_reg_load←100, rd_reg_load 保持 x2
           addi x3 进入 ID/EX → posedge K+2 采样
Cycle K+2 (EX): addi x3 使用前递
                  !load_lock=1, rd_reg_load=x2==rs1 → rs1_data_final=100 ✓
                  结果: 100+1=101 ✓
```

---

## 第三轮修复（仿真 T4 失败触发）

仿真结果：`x3=15`（期望 25）、`x4=25`（期望 40）——值恰好偏移一拍，
说明 register_EX 的 1-back 前递正常，但 **2 条指令前**的结果读到了寄存器堆旧值 0。

---

### Bug 10：BRAM 寄存器堆读地址来自错误的流水级

**文件**：`src/RTL/core/core_top.v`

**问题**：`reg_file_bram` 使用 `(* ram_style = "block" *)` 实现，读操作是
registered（posedge 采样 `raddr`，下一拍输出 `rdata`）。原设计将读地址连接到
ID/EX 寄存器的**输出** `rs1_out`/`rs2_out`（EX 阶段地址），导致读数据比
指令进入 EX 晚一拍。

时序追踪（`add x3, x2, x1`，x1=10, x2=15）：

```
posedge 4: ID/EX 锁存 add x3 → rs1_out 变为 x2
           regfile 采样旧地址 x1（addi x2 的 rs1）
           → rdata2 读到 regs[x0]=0（更早一拍的地址）

posedge 5: regfile 采样 x1（add x3 的 rs2）→ 但 EX 已完成
```

结果：rs2 没有 register_EX 前递匹配（rd_reg=x2≠x1），回退到 `rf_rdata2=0`。
x3 = 15 + 0 = 15。

**修复**：读地址改为 **ID 阶段**组合输出 `id_rs1`/`id_rs2`。这样 posedge N（ID→EX
转换）采样的是即将进入 EX 的指令的源寄存器地址，`rdata` 在 EX 期间立即可用。
同时 regfile 内部的写旁路（`raddr==waddr → rdata<=wdata`）自然覆盖"2 条指令前"
的 WB 写回场景。

```verilog
// 旧
.raddr1(rs1_out),
.raddr2(rs2_out),

// 新
.raddr1(id_rs1),
.raddr2(id_rs2),
```

**修复后前递覆盖**：

| 距离 | 来源 | 机制 |
|------|------|------|
| 1-back (N-1→N) | register_EX | `forward_rd_in == ex_rs1` 直接前递 |
| 2-back (N-2→N) | regfile WB bypass | posedge N 时 WB 写 regs[A-2.rd]，同拍 regfile 旁路给 rdata |
| 3-back+ | regfile | 值已提交到 regs，正常读取 |

---

### Bug 11：`load_status_out` 悬空（register_MEM 已移除的遗留问题）

**文件**：`src/RTL/core/core_top.v`

**问题**：第二轮修复删除了 `register_MEM` 实例及 `wire load_status_out` 声明，
但 `EX_WB_reg` 仍引用 `.load_occupation(load_status_out)`。
`load_status_out` 变为隐式 1-bit wire，无驱动源（值为 `z`/`x`），
当 `stall_back=1` 时 `stall_final = stall & x = x`，可能导致 EX_WB 行为不确定。

**修复**：将 `load_occupation` 绑定为 `1'b0`。对理想存储器（`dmem_rvalid=1`）
`stall_back` 恒为 0，`stall_final = 0 & 0 = 0`，与原行为一致。

```verilog
// 旧
.load_occupation(load_status_out),

// 新
.load_occupation(1'b0),
```

---

## 改动文件汇总（完整）

| 文件 | 累计改动 | 对应 Bug |
|------|--------|----------|
| `src/RTL/core/EX.v` | 3 处 | Bug 2、Bug 3、Bug 4 |
| `src/RTL/module/register_EX.v` | 4 处 | Bug 5、Bug 9 |
| `src/RTL/core/core_top.v` | 8 处 | Bug 1、Bug 6、Bug 7、Bug 8、Bug 10、Bug 11 |

---

## 第四轮：综合 / 上板与 `program.hex`（Vivado）

本节记录与 FPGA 综合、指令存储器初始化、顶层 I/O 相关的修改与操作说明（非 CPU 功能 Bug 编号）。

### `program.hex` 内容与含义

仓库根目录文件：`program.hex`（`$readmemh` 格式：每行一条 32 位指令的十六进制，**无** `0x` 前缀）。

| 地址(字) | 机器码 | 汇编（示意） | 说明 |
|---------|--------|--------------|------|
| 0 | `00a00093` | `addi x1, x0, 10` | x1 = 10 |
| 1 | `00508113` | `addi x2, x1, 5` | x2 = 15 |
| 2 | `001101b3` | `add  x3, x2, x1` | x3 = 25 |
| 3 | `00218233` | `add  x4, x3, x2` | x4 = 40 |
| 4～31 | `00000013` | `nop`（`addi x0,x0,0`） | 填充，便于观察后续 PC |

上板后可通过 `fpga_top` 的 `led[7:0]`（接 `ex_result_out[7:0]`）看到 EX 阶段结果低位在变化；寄存器最终值需仿真或 ILA 观测。

### 为何不把 `.hex` 加进 Vivado「源文件」

Vivado 的 **Design Sources / Simulation Sources** 面向 **RTL/SystemVerilog** 等可编译源；
`program.hex` 是 **数据文件**，一般**不要**、也**不必**作为 RTL 源加入工程。

综合阶段若仅靠 `$readmemh("program.hex", ...)`，工具要在磁盘上找该路径，容易因
工程目录与仓库目录不一致而失败，且会误以为 `parameter FILE=""` 时「没有加载程序」。

**当前方案（推荐）**：把指令镜像**写进 RTL 可 `include` 的片段**  
`src/RTL/memory/inst_mem_program.vh`，由 `inst_mem.v` 在 `initial` 里 `` `include `` 展开。
这样综合/实现**不依赖**外部 `.hex`，也**不需要**在 Vivado 里添加 `program.hex`。

根目录 `program.hex` 仍保留，作为**人类可读备份**；修改程序后请**同步更新**
`inst_mem_program.vh`（或用手写脚本从 hex 生成 vh）。

### 仿真时可选：`$readmemh` 覆盖（非综合）

`inst_mem` 仍保留 `parameter FILE = ""`。在**仿真**中且**未定义** `SYNTHESIS` 时，
若 `FILE != ""`，会在内联镜像之后执行 `$readmemh(FILE, mem)` 覆盖 `mem`
（例如自定义 testbench 传入十六进制文件路径）。  
**综合时** Vivado 会定义 `SYNTHESIS`，上述 `$readmemh` 被 `` `ifndef SYNTHESIS `` 屏蔽，
避免路径问题。

### `inst_mem.v`（指令 ROM）相关修改摘要

| 项目 | 说明 |
|------|------|
| `timescale` | 去掉行尾多余分号，避免工具按严格 Verilog 解析报错。 |
| `for` 循环 | `for(integer i=...)` 改为模块级 `integer i;` + `for (i=0;...)`，兼容 Vivado Verilog 模式。 |
| `ram_style` | `distributed`：组合读与 BRAM 同步读模型不符；分布式存储利于综合保留初始化内容。 |
| 初始化 | 先整片 NOP，再 `` `include "inst_mem_program.vh" `` 写入字 0..31；仿真可选 `$readmemh`。 |

### `soc_top.v` 中 `inst_mem` 实例化

- **默认**无参数：`inst_mem u_inst_mem (...)`。程序来自 `inst_mem_program.vh`，**不再**传 `FILE`，
  避免「看起来 FILE 为空、综合未加载」的误解。

### `fpga_top.v`（上板顶层）与 I/O 问题

| 现象 | 原因 | 处理 |
|------|------|------|
| Place 报 **424 I/O** | 以 `soc_top`/`core_top` 为顶层时，大量调试口被当成封装引脚 | 使用 `fpga_top`，仅引出 `clk`、`rst_n`、`led[7:0]` |
| **The design is empty** | 内部信号未驱动到顶层输出，opt 裁掉全部逻辑 | `assign led = ex_result_out_w[7:0]` + 对 `soc_top` 实例加 `(* dont_touch = "yes" *)` 作保险 |

文件路径：`src/RTL/core/fpga_top.v`。

### 约束文件 `constraints/fpga_top.xdc`

- 为 `clk`、`rst_n`、`led[7:0]` 提供示例 `PACKAGE_PIN` / `IOSTANDARD` / `create_clock`。
- **必须按实际开发板原理图修改引脚**，否则实现阶段会失败或功能错误。
- 在 Vivado 中：`Add Sources` → **Add or create constraints**，加入该 `.xdc`。

### 第四轮涉及文件一览

| 文件 | 作用 |
|------|------|
| `program.hex` | 人类可读指令列表（与 vh 同步）；**不必**加入 Vivado |
| `src/RTL/memory/inst_mem_program.vh` | 指令初值片段，供 `inst_mem.v` `` `include ``（综合/仿真均有效） |
| `src/RTL/memory/inst_mem.v` | 语法、RAM 风格、`include` + 可选仿真 `$readmemh` |
| `src/RTL/core/soc_top.v` | 默认例化 `inst_mem`（无 FILE） |
| `src/RTL/core/fpga_top.v` | 最小引脚顶层 + LED 观测 |
| `constraints/fpga_top.xdc` | 引脚与时钟约束模板 |

### 改动文件汇总（第四轮：综合/上板）

| 文件 | 说明 |
|------|------|
| `program.hex` | 可验证 ALU 链 + NOP 填充（与 vh 对齐） |
| `src/RTL/memory/inst_mem_program.vh` | 内联镜像（综合不依赖外部文件） |
| `src/RTL/memory/inst_mem.v` | `include` vh；`ifndef SYNTHESIS` 下可选 `$readmemh` |
| `src/RTL/core/soc_top.v` | 去掉 `.FILE("program.hex")` 参数化例化 |
| `src/RTL/core/fpga_top.v` | 最小 I/O 顶层 |
| `constraints/fpga_top.xdc` | 约束模板 |
