# uart_hello.S — 最简 UART 输出验证程序
#
# 通过手写汇编 + 软件延迟循环，在 Basys3 上发送 "Hi\r\n" 来验证:
#   1. CPU 上板能正常运行
#   2. UART TX 模块和引脚映射正确
#   3. USB-UART 桥和 pyserial 可以收到正确字符
#
# 构建 (在 scripts/sw 目录):
#   make hello
#
# 部署:
#   将 build/uart_hello.hex 内容复制到 inst_mem_program.vh 的 mem[] 数组，重新综合

.section .text.start
.global _start

_start:
    auipc  sp, 0x1               # sp = 0x1000 (沿用标准启动栈指针)
    addi   sp, sp, 0
    jal    ra, main
1:  jal    x0, 1b                 # main 不应返回；返回时在此死循环

main:
    lui    s0, 0x10001            # s0 = 0x10001000 (UART TX 地址)

send_loop:
    # ---- 发送 "Hi\r\n" ----
    li     a0, 'H'
    call   uart_putc
    li     a0, 'i'
    call   uart_putc
    li     a0, '\r'
    call   uart_putc
    li     a0, '\n'
    call   uart_putc

    # ---- 消息间长延迟 (约1秒@50MHz) ----
    lui    t2, 0x0C
    addi   t2, t2, 0x350         # t2 = 50000
1:  li     t1, 1000
2:  addi   t1, t1, -1
    bnez   t1, 2b
    addi   t2, t2, -1
    bnez   t2, 1b

    j      send_loop

# ---- UART 发送子程序 ----
# 输入: a0 = 字符 (低8位)
# 使用软件延迟保证不丢字符 (每字符 ~5000 循环, 远大于 115200 baud 所需 ~4340)
uart_putc:
    li     t0, 5000
1:  addi   t0, t0, -1
    bnez   t0, 1b
    sb     a0, 0(s0)             # *UART_TX = a0
    jalr   x0, ra, 0             # ret
