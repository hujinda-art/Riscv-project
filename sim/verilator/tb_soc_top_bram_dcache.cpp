// ============================================================================
// tb_soc_top_bram_dcache.cpp — Verilator wrapper for soc_top_bram_dcache tests
//
// Tests:
//   +TEST=m_extension  → tb_m_extension (MUL/DIV/REM + divide-by-zero)
//   +TEST=dcache_sys   → tb_dcache_sys (SW/LW, miss, cache lines, sub-word)
// ============================================================================

#include "Vsoc_top_bram_dcache.h"
#include "Vsoc_top_bram_dcache___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>

// Ports (direct access)
#define CLK      top->clk
#define RST_N    top->rst_n
#define STALL    top->stall
#define FLUSH    top->flush
#define EXCEPT   top->exception
#define PC_EX    top->pc_exception
#define INTR     top->__SYM__interrupt
#define PC_INTR  top->pc_interrupt

// Internal signals via rootp
#define R        rootp
#define IMEM_MEM R->soc_top_bram_dcache__DOT__u_inst_mem__DOT__mem
#define REGS     R->soc_top_bram_dcache__DOT__u_core__DOT__u_regfile__DOT__regs
#define M0       R->soc_top_bram_dcache__DOT__u_data_mem__DOT__mem0
#define M1       R->soc_top_bram_dcache__DOT__u_data_mem__DOT__mem1
#define M2       R->soc_top_bram_dcache__DOT__u_data_mem__DOT__mem2
#define M3       R->soc_top_bram_dcache__DOT__u_data_mem__DOT__mem3

static uint64_t timestamp = 0;

static void tick(Vsoc_top_bram_dcache *top, VerilatedVcdC *tfp, bool clk_val) {
    CLK = clk_val;
    top->eval();
    if (tfp) { tfp->dump(timestamp); timestamp += 5; }
}

static void imem_write(Vsoc_top_bram_dcache *top, int idx, uint32_t val) {
    Vsoc_top_bram_dcache___024root *rootp = top->rootp;
    IMEM_MEM[idx] = val;
}
static uint32_t reg_read(Vsoc_top_bram_dcache *top, int i) {
    Vsoc_top_bram_dcache___024root *rootp = top->rootp;
    return REGS[i];
}
static void reg_write(Vsoc_top_bram_dcache *top, int i, uint32_t val) {
    Vsoc_top_bram_dcache___024root *rootp = top->rootp;
    REGS[i] = val;
}
static void dmem_byte_set(Vsoc_top_bram_dcache *top, int lane, int wi, uint8_t val) {
    Vsoc_top_bram_dcache___024root *rootp = top->rootp;
    switch (lane) {
        case 0: M0[wi] = val; break;
        case 1: M1[wi] = val; break;
        case 2: M2[wi] = val; break;
        case 3: M3[wi] = val; break;
    }
}
static void dmem_write_word(Vsoc_top_bram_dcache *top, int wi, uint32_t val) {
    dmem_byte_set(top, 0, wi, val & 0xFF);
    dmem_byte_set(top, 1, wi, (val >> 8) & 0xFF);
    dmem_byte_set(top, 2, wi, (val >> 16) & 0xFF);
    dmem_byte_set(top, 3, wi, (val >> 24) & 0xFF);
}

static void do_reset(Vsoc_top_bram_dcache *top, VerilatedVcdC *tfp) {
    RST_N = 0; top->eval();
    for (int i = 0; i < 1024; i++) imem_write(top, i, 0x00000013);
    for (int i = 0; i < 1024; i++) dmem_write_word(top, i, 0);
    for (int i = 1; i < 32; i++) reg_write(top, i, 0);
    for (int i = 0; i < 2; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
    RST_N = 1;
}

// ============================================================================
static int run_m_extension(Vsoc_top_bram_dcache *top, VerilatedVcdC *tfp) {
    printf("\n=== tb_m_extension ===\n");
    int pass = 0, fail = 0;

    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS [%s] = 0x%08X\n", msg, got); pass++; }
        else { printf("  FAIL [%s] got=0x%08X expected=0x%08X\n", msg, got, exp); fail++; }
    };

    RST_N = 0; STALL = 0; FLUSH = 0; EXCEPT = 0; PC_EX = 0; INTR = 0; PC_INTR = 0;
    top->eval();
    do_reset(top, tfp);

    // Init registers
    imem_write(top, 0,  0x00600093); // addi x1, x0, 6
    imem_write(top, 1,  0x00700113); // addi x2, x0, 7
    imem_write(top, 2,  0x80000193); // addi x3, x0, 0x800
    imem_write(top, 3,  0x80000237); // lui  x4, 0x80000
    imem_write(top, 4,  0xFFF00293); // addi x5, x0, -1
    imem_write(top, 5,  0x00000313); // addi x6, x0, 0
    imem_write(top, 6,  0x00300393); // addi x7, x0, 3
    imem_write(top, 7,  0x00000013); // nop
    imem_write(top, 8,  0x00000013); // nop
    imem_write(top, 9,  0x00000013); // nop

    // MUL/MULH/MULHU/MULHSU
    imem_write(top, 10, 0x02208433); // MUL    x8,  x1, x2
    imem_write(top, 11, 0x022094B3); // MULH   x9,  x1, x2
    imem_write(top, 12, 0x02521533); // MULH   x10, x4, x5
    imem_write(top, 13, 0x025235B3); // MULHU  x11, x4, x5
    imem_write(top, 14, 0x02122633); // MULHSU x12, x4, x1
    imem_write(top, 15, 0x00000013); // nop

    // DIV/DIVU
    imem_write(top, 16, 0x027146B3); // DIV    x13, x2, x7
    imem_write(top, 17, 0x02524733); // DIV    x14, x4, x5
    imem_write(top, 18, 0x027257B3); // DIVU   x15, x4, x7
    imem_write(top, 19, 0x00000013); // nop

    // REM/REMU
    imem_write(top, 20, 0x02716833); // REM    x16, x2, x7
    imem_write(top, 21, 0x025268B3); // REM    x17, x4, x5
    imem_write(top, 22, 0x02727933); // REMU   x18, x4, x7
    imem_write(top, 23, 0x00000013); // nop

    // Divide-by-zero
    imem_write(top, 24, 0x0260C9B3); // DIV    x19, x1, x6
    imem_write(top, 25, 0x0260DA33); // DIVU   x20, x1, x6
    imem_write(top, 26, 0x0260EAB3); // REM    x21, x1, x6
    imem_write(top, 27, 0x0260FB33); // REMU   x22, x1, x6

    for (int i = 0; i < 120; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }

    printf("--- Initial register checks ---\n");
    check(1, 0x00000006, "Init  x1=6");
    check(2, 0x00000007, "Init  x2=7");
    check(4, 0x80000000, "Init  x4=0x80000000");
    check(5, 0xFFFFFFFF, "Init  x5=-1");
    check(6, 0x00000000, "Init  x6=0");
    check(7, 0x00000003, "Init  x7=3");

    printf("--- MUL / MULH / MULHU / MULHSU (stubbed -> 0) ---\n");
    check(8,  0, "MUL      6*7      (stubbed→0)");
    check(9,  0, "MULH     hi(6*7)  (stubbed→0)");
    check(10, 0, "MULH     hi(0x80000000*-1) (stubbed→0)");
    check(11, 0, "MULHU    hi(0x80000000*0xFFFFFFFF) (stubbed→0)");
    check(12, 0, "MULHSU   hi(0x80000000*6) (stubbed→0)");

    printf("--- DIV / DIVU (stubbed -> 0) ---\n");
    check(13, 0, "DIV      7/3      (stubbed→0)");
    check(14, 0, "DIV      overflow (stubbed→0)");
    check(15, 0, "DIVU     0x80000000/3 (stubbed→0)");

    printf("--- REM / REMU (stubbed -> 0) ---\n");
    check(16, 0, "REM      7%3      (stubbed→0)");
    check(17, 0, "REM      overflow (stubbed→0)");
    check(18, 0, "REMU     0x80000000%3 (stubbed→0)");

    printf("--- Divide by Zero (stubbed -> 0) ---\n");
    check(19, 0, "DIV/0    6/0      (stubbed→0)");
    check(20, 0, "DIVU/0   6/0      (stubbed→0)");
    check(21, 0, "REM/0    6%0      (stubbed→0)");
    check(22, 0, "REMU/0   6%0      (stubbed→0)");

    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    printf("NOTE: M extension is stubbed to 0; all M results are expected to be 0.\n");
    return (fail > 0) ? 1 : 0;
}

static int run_dcache_sys(Vsoc_top_bram_dcache *top, VerilatedVcdC *tfp) {
    printf("\n=== tb_dcache_sys ===\n");
    int pass = 0, fail = 0;

    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS [%s] = 0x%08X\n", msg, got); pass++; }
        else { printf("  FAIL [%s] got=0x%08X expected=0x%08X\n", msg, got, exp); fail++; }
    };

    auto run_cycles = [&](int n) {
        for (int i = 0; i < n; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
    };

    // T1: SW then LW same address
    printf("--- TEST 1: SW then LW same address ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x05500093); imem_write(top, 1, 0x01000113);
    imem_write(top, 2, 0x00112023); imem_write(top, 3, 0x00012183);
    run_cycles(60);
    check(1, 0x55, "T1 data      x1=0x55");
    check(3, 0x55, "T1 LW result x3=0x55");

    // T2: LW miss → refill → LW hit
    printf("--- TEST 2: LW miss refill + LW hit ---\n");
    do_reset(top, tfp);
    dmem_byte_set(top, 0, 8, 0xDD); dmem_byte_set(top, 1, 8, 0xCC);
    dmem_byte_set(top, 2, 8, 0xBB); dmem_byte_set(top, 3, 8, 0xAA);
    imem_write(top, 0, 0x02000113); imem_write(top, 1, 0x00012083);
    imem_write(top, 2, 0x00012183);
    run_cycles(80);
    check(1, 0xAABBCCDD, "T2 LW miss    x1=AABBCCDD");
    check(3, 0xAABBCCDD, "T2 LW hit     x3=AABBCCDD");

    // T3: Different cache lines
    printf("--- TEST 3: Different cache lines ---\n");
    do_reset(top, tfp);
    imem_write(top, 0,  0x01100093); imem_write(top, 1,  0x03000393);
    imem_write(top, 2,  0x0013A023); imem_write(top, 3,  0x04200193);
    imem_write(top, 4,  0x05000413); imem_write(top, 5,  0x00342023);
    imem_write(top, 6,  0x00000013); imem_write(top, 7,  0x00000013);
    imem_write(top, 8,  0x00042283); imem_write(top, 9,  0x00000013);
    imem_write(top, 10, 0x0003A303);
    run_cycles(100);
    check(5, 0x42, "T3 line5      x5=0x42");
    check(6, 0x11, "T3 line3      x6=0x11");

    // T4: Sub-word SB/LB
    printf("--- TEST 4: Sub-word SB/LB ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x07B00093); imem_write(top, 1, 0x04000113);
    imem_write(top, 2, 0x00110023); imem_write(top, 3, 0x00010183);
    run_cycles(60);
    check(3, 0x7B, "T4 SB/LB       x3=0x7B");

    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    return (fail > 0) ? 1 : 0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    std::string test_name, wave_path;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg.find("+TEST=") == 0)      test_name = arg.substr(6);
        else if (arg.find("+WAVE=") == 0) wave_path = arg.substr(6);
    }

    if (test_name.empty()) {
        fprintf(stderr, "Usage: %s +TEST=<m_extension|dcache_sys> [+WAVE=<path>]\n", argv[0]);
        return 1;
    }

    Vsoc_top_bram_dcache *top = new Vsoc_top_bram_dcache;
    STALL = 0; FLUSH = 0; EXCEPT = 0; PC_EX = 0; INTR = 0; PC_INTR = 0;

    VerilatedVcdC *tfp = nullptr;
    if (!wave_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(wave_path.c_str());
        printf("Waveform: %s\n", wave_path.c_str());
    }

    int result = 0;
    if (test_name == "m_extension")      result = run_m_extension(top, tfp);
    else if (test_name == "dcache_sys")  result = run_dcache_sys(top, tfp);
    else { fprintf(stderr, "Unknown test: %s\n", test_name.c_str()); result = 1; }

    if (tfp) { tfp->close(); delete tfp; }
    top->final();
    delete top;
    return result;
}
