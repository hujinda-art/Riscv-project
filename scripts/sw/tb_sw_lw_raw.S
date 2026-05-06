/* 最小程序：验证 SW→LW RAW hazard 通过 DMEM。
 * SW 存 0x11223344 到 0x200，LW 从 0x200 读回，写 SIG[17]，写 DONE。
 * 期望 SIG[17] = 0x11223344（load 读到 store 写入的值）。
 */
.section .text
.global main

main:
    lui     a4, 0x11223
    addi    a4, a4, 0x344       /* a4 = 0x11223344 */
    li      a5, 0x200
    sw      a4, 0(a5)           /* store to 0x200 */
    lw      a5, 0(a5)           /* load from 0x200 → should get 0x11223344 */
    /* sig[17] @ 0x100 + 17*4 = 0x144 => offset 324(zero) */
    sw      a5, 324(zero)
    lui     a5, 0xc001d
    addi    a5, a5, 13
    sw      a5, 128(zero)       /* DONE @ 0x80 */
1:
    j       1b
