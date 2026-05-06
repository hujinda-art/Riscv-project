# sum1to100.S — 计算 1+2+...+100 = 5050 并通过 UART 输出
#
# 输出 "Result: 5050\r\n" 后延迟重复
#
# 构建: cd scripts/sw && make sum100
# 部署: 将 build/sum1to100.hex 复制到 inst_mem_program.vh

.section .text
.global main

# ================================================================
# main: 计算 1+...+100，将结果转为十进制 ASCII，通过 UART 输出
# ================================================================
main:
    # ---- 步骤 1: 计算 1 到 100 的和 ----
    li     a0, 0              # sum = 0
    li     a1, 1              # i = 1
    li     a2, 100            # limit = 100
sum_lp:
    add    a0, a0, a1         # sum += i
    addi   a1, a1, 1          # i++
    bge    a2, a1, sum_lp     # if limit >= i, continue
    # a0 = 5050 = 0x13BA

    # ---- 步骤 2: 发送 "Result: " 前缀 ----
    lui    s0, 0x10001        # s0 = 0x10001000 (UART TX)

    li     a0, 'R'; call uart_putc
    li     a0, 'e'; call uart_putc
    li     a0, 's'; call uart_putc
    li     a0, 'u'; call uart_putc
    li     a0, 'l'; call uart_putc
    li     a0, 't'; call uart_putc
    li     a0, ':'; call uart_putc
    li     a0, ' '; call uart_putc

    # ---- 步骤 3: 重新计算 sum (uart_putc 破坏了 a0) ----
    li     a0, 0
    li     a1, 1
    li     a2, 100
1:  add    a0, a0, a1
    addi   a1, a1, 1
    bge    a2, a1, 1b
    # a0 = 5050

    # ---- 步骤 4: 将 a0 转为十进制 ASCII，压入栈缓冲区 ----
    addi   sp, sp, -16        # 栈上分配 16 字节
    mv     t0, sp             # t0 = 缓冲区基地址
    mv     t1, a0             # t1 = 待转换的数
    li     t5, 0              # t5 = 位数计数

cvt_lp:
    # 除以 10: 商→t1, 余数→t3
    mv     t3, t1
    li     t1, 0
2:  addi   t3, t3, -10
    blt    t3, zero, 3f
    addi   t1, t1, 1
    j      2b
3:  addi   t3, t3, 10         # 恢复余数 (0..9)
    addi   t3, t3, '0'        # → ASCII
    add    t4, t0, t5
    sb     t3, 0(t4)          # buffer[t5] = digit
    addi   t5, t5, 1
    bnez   t1, cvt_lp

    # ---- 步骤 5: 逆序输出 (buffer[t5-1] → buffer[0]) ----
out_lp:
    mv     t2, t5             # t2 = 剩余位数

out_digit:
    beqz   t2, out_nl
    addi   t2, t2, -1
    add    t4, t0, t2         # 逆向索引
    lbu    a0, 0(t4)
    call   uart_putc
    j      out_digit

out_nl:
    li     a0, '\r'; call uart_putc
    li     a0, '\n'; call uart_putc

    # ---- 步骤 6: 长延迟后重复 ----
    addi   sp, sp, 16         # 恢复栈指针
    li     a4, 200000
4:  addi   a4, a4, -1
    bnez   a4, 4b
    j      main

# ================================================================
# uart_putc: 通过 UART 发送一个字符 (软件延迟版本)
# 输入: a0 = 字符 (低 8 位)
# 延迟 ~5000 周期，适配 100MHz → 115200 baud
# ================================================================
uart_putc:
    addi   sp, sp, -4
    sw     ra, 0(sp)
    li     t6, 5000
5:  addi   t6, t6, -1
    bnez   t6, 5b
    sb     a0, 0(s0)          # *UART_TX = char
    lw     ra, 0(sp)
    addi   sp, sp, 4
    jalr   x0, ra, 0
