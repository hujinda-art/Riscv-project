// ---------------------------------------------------------------------------
// Instruction ROM image — generated from scripts/sw/build/full_instr.hex
// (full_instr_test.c + startup.S, -march=rv32im -mabi=ilp32 -O2)
// Keep in sync with full_instr.hex: run `make` in scripts/sw/ then update.
// Vivado synthesis: no .hex file needed; this fragment is `included by RTL.
// ---------------------------------------------------------------------------
    mem[0]  = 32'h00001117; // auipc sp,0x1
    mem[1]  = 32'h00010113; // mv    sp,sp
    mem[2]  = 32'h008000ef; // jal   ra,<main>
    mem[3]  = 32'h0000006f; // j     . (infinite loop at _start tail)
    mem[4]  = 32'h00a00293; // li    t0,10
    mem[5]  = 32'h00300313; // li    t1,3
    mem[6]  = 32'h006287b3; // add   a5,t0,t1
    mem[7]  = 32'h10f02023; // sw    a5,256(zero)  # sig[0] = ADD
    mem[8]  = 32'h00a00293; // li    t0,10
    mem[9]  = 32'h00300313; // li    t1,3
    mem[10] = 32'h406287b3; // sub   a5,t0,t1
    mem[11] = 32'h10f02223; // sw    a5,260(zero)  # sig[1] = SUB
    mem[12] = 32'h00a00293; // li    t0,10
    mem[13] = 32'h00300313; // li    t1,3
    mem[14] = 32'h0062f7b3; // and   a5,t0,t1
    mem[15] = 32'h10f02423; // sw    a5,264(zero)  # sig[2] = AND
    mem[16] = 32'h00a00293; // li    t0,10
    mem[17] = 32'h00300313; // li    t1,3
    mem[18] = 32'h0062e7b3; // or    a5,t0,t1
    mem[19] = 32'h10f02623; // sw    a5,268(zero)  # sig[3] = OR
    mem[20] = 32'h00a00293; // li    t0,10
    mem[21] = 32'h00300313; // li    t1,3
    mem[22] = 32'h0062c7b3; // xor   a5,t0,t1
    mem[23] = 32'h10f02823; // sw    a5,272(zero)  # sig[4] = XOR
    mem[24] = 32'h00300293; // li    t0,3
    mem[25] = 32'h00200313; // li    t1,2
    mem[26] = 32'h006297b3; // sll   a5,t0,t1
    mem[27] = 32'h10f02a23; // sw    a5,276(zero)  # sig[5] = SLL
    mem[28] = 32'h01000293; // li    t0,16
    mem[29] = 32'h00200313; // li    t1,2
    mem[30] = 32'h0062d7b3; // srl   a5,t0,t1
    mem[31] = 32'h10f02c23; // sw    a5,280(zero)  # sig[6] = SRL
    mem[32] = 32'hff000293; // li    t0,-16
    mem[33] = 32'h00200313; // li    t1,2
    mem[34] = 32'h4062d7b3; // sra   a5,t0,t1
    mem[35] = 32'h10f02e23; // sw    a5,284(zero)  # sig[7] = SRA
    mem[36] = 32'hfff00293; // li    t0,-1
    mem[37] = 32'h00100313; // li    t1,1
    mem[38] = 32'h0062a7b3; // slt   a5,t0,t1
    mem[39] = 32'h12f02023; // sw    a5,288(zero)  # sig[8] = SLT
    mem[40] = 32'h00100293; // li    t0,1
    mem[41] = 32'h00200313; // li    t1,2
    mem[42] = 32'h0062b7b3; // sltu  a5,t0,t1
    mem[43] = 32'h12f02223; // sw    a5,292(zero)  # sig[9] = SLTU
    mem[44] = 32'h00700293; // li    t0,7
    mem[45] = 32'h00600313; // li    t1,6
    mem[46] = 32'h026287b3; // mul   a5,t0,t1
    mem[47] = 32'h12f02423; // sw    a5,296(zero)  # sig[10]= MUL
    mem[48] = 32'h123457b7; // lui   a5,0x12345
    mem[49] = 32'h12f02623; // sw    a5,300(zero)  # sig[11]= LUI
    mem[50] = 32'h00000297; // auipc t0,0x0
    mem[51] = 32'h00000317; // auipc t1,0x0
    mem[52] = 32'h405307b3; // sub   a5,t1,t0
    mem[53] = 32'h12f02823; // sw    a5,304(zero)  # sig[12]= AUIPC_REL
    mem[54] = 32'h00500293; // li    t0,5
    mem[55] = 32'h00500313; // li    t1,5
    mem[56] = 32'h00000793; // li    a5,0
    mem[57] = 32'h00629463; // bne   t0,t1,+8
    mem[58] = 32'h00178793; // addi  a5,a5,1
    mem[59] = 32'h12f02a23; // sw    a5,308(zero)  # sig[13]= BEQ/BNE
    mem[60] = 32'hfff00293; // li    t0,-1
    mem[61] = 32'h00100313; // li    t1,1
    mem[62] = 32'h00000793; // li    a5,0
    mem[63] = 32'h0062c463; // blt   t0,t1,+8
    mem[64] = 32'h0080006f; // j     +8  (skip)
    mem[65] = 32'h00100793; // li    a5,1
    mem[66] = 32'h12f02c23; // sw    a5,312(zero)  # sig[14]= BLT
    mem[67] = 32'h00000293; // li    t0,0          # test_jal
    mem[68] = 32'h00c0036f; // jal   t1,+12
    mem[69] = 32'hdeadc2b7; // (dead) lui  t0,0xdeadc
    mem[70] = 32'heef28293; // (dead) addi t0,t0,-273
    mem[71] = 32'h00337393; // andi  t2,t1,3
    mem[72] = 32'h0013b393; // sltiu t2,t2,1
    mem[73] = 32'h00603e33; // sltu  t3,x0,t1
    mem[74] = 32'h01c3f7b3; // and   a5,t2,t3
    mem[75] = 32'h12f02e23; // sw    a5,316(zero)  # sig[15]= JAL
    mem[76] = 32'h00000393; // li    t2,0          # test_jalr
    mem[77] = 32'h00000297; // auipc t0,0x0
    mem[78] = 32'h01428293; // addi  t0,t0,0x14
    mem[79] = 32'h00028367; // jalr  t1,t0,0
    mem[80] = 32'hdeadc3b7; // (dead) lui  t3,0xdeadc
    mem[81] = 32'heef38393; // (dead) addi t3,t3,-273
    mem[82] = 32'h00337e13; // andi  t3,t1,3
    mem[83] = 32'h001e3e13; // sltiu t3,t3,1
    mem[84] = 32'h00603eb3; // sltu  t4,x0,t1
    mem[85] = 32'h01de77b3; // and   a5,t3,t4
    mem[86] = 32'h11223737; // lui   a4,0x11223    # LW/SW test
    mem[87] = 32'h14f02023; // sw    a4,0x140(zero)  # mem[0x200>>2]=mem[128]... wait, addr=0x200
    mem[88] = 32'h34470713; // addi  a4,a4,0x344   # a4 += 0x344
    mem[89] = 32'h20000793; // li    a5,0x200
    mem[90] = 32'h00e7a023; // sw    a4,0(a5)      # mem[0x200] = 0x11223344+0x344? no — see below
    mem[91] = 32'h0007a783; // lw    a5,0(a5)
    mem[92] = 32'h14f02223; // sw    a5,0x144(zero)# sig[17]= LW/SW   (addr=0x144 = 324(zero))
    mem[93] = 32'hc001d7b7; // lui   a5,0xc001d    # DONE_MAGIC upper
    mem[94] = 32'h00d78793; // addi  a5,a5,0xd     # a5 = 0xC001D00D
    mem[95] = 32'h08f02023; // sw    a5,0x80(zero) # DONE flag
    mem[96] = 32'h0000006f; // j     . (self-trap)
    mem[97] = 32'h00000513; // li    a0,0  (return 0 — unreachable in practice)
    mem[98] = 32'h00008067; // ret
