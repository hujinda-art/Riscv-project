/* 最小程序：仅测 LUI+ADDI、SW/LW 到 0x200、写 SIG[17]、写 DONE，无 BLT。
 * 若本用例通过而 tb_system_soc 中 SIG[17]/DONE 错，可怀疑访存/写回时序。
 */
.section .text
.global main

main:
    lui     a4, 0x11223
    addi    a4, a4, 0x344
    li      a5, 0x200
    sw      a4, 0(a5)
    lw      a5, 0(a5)
    /* sig[17] @ 0x100 + 17*4 = 0x144 => offset 324(zero) */
    sw      a5, 324(zero)
    lui     a5, 0xc001d
    addi    a5, a5, 13
    sw      a5, 128(zero)
1:
    j       1b
