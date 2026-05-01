/* 最小程序：仅测 BLT + 写 SIG[14] + 写 DONE，无 LW/SW。
 * 若 tb_system_soc 中 SIG[14] 错而算术对，可单独跑本用例验证 EX 前递/分支冒险。
 */
.section .text
.global main

main:
    li      t0, -1
    li      t1, 1
    li      a5, 0
    blt     t0, t1, 1f
    j       2f
1:
    addi    a5, a5, 1
2:
    /* sig[14] @ 0x100 + 14*4 = 0x138  => offset 312(zero) */
    sw      a5, 312(zero)
    lui     a5, 0xc001d
    addi    a5, a5, 13
    sw      a5, 128(zero)
3:
    j       3b
