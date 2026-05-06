// ============================================================================
// tb_soc_top_bram_icache.cpp — Verilator wrapper for soc_top_bram_icache tests
// ============================================================================

#include "Vsoc_top_bram_icache.h"
#include "Vsoc_top_bram_icache___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>

#define CLK     top->clk
#define RST_N   top->rst_n
#define STALL   top->stall
#define FLUSH   top->flush
#define EXCEPT  top->exception
#define PC_EX   top->pc_exception
#define INTR    top->__SYM__interrupt
#define PC_INTR top->pc_interrupt

#define R       rootp
#define IMEM_MEM R->soc_top_bram_icache__DOT__u_inst_mem__DOT__mem
#define REGS     R->soc_top_bram_icache__DOT__u_core__DOT__u_regfile__DOT__regs
#define M0       R->soc_top_bram_icache__DOT__u_data_mem__DOT__mem0
#define M1       R->soc_top_bram_icache__DOT__u_data_mem__DOT__mem1
#define M2       R->soc_top_bram_icache__DOT__u_data_mem__DOT__mem2
#define M3       R->soc_top_bram_icache__DOT__u_data_mem__DOT__mem3

static uint64_t timestamp = 0;

static void tick(Vsoc_top_bram_icache *top, VerilatedVcdC *tfp, bool clk_val) {
    CLK = clk_val;
    top->eval();
    if (tfp) { tfp->dump(timestamp); timestamp += 5; }
}

static void imem_write(Vsoc_top_bram_icache *top, int idx, uint32_t val) {
    Vsoc_top_bram_icache___024root *rootp = top->rootp;
    IMEM_MEM[idx] = val;
}
static uint32_t reg_read(Vsoc_top_bram_icache *top, int i) {
    Vsoc_top_bram_icache___024root *rootp = top->rootp;
    return REGS[i];
}
static void reg_write(Vsoc_top_bram_icache *top, int i, uint32_t val) {
    Vsoc_top_bram_icache___024root *rootp = top->rootp;
    REGS[i] = val;
}
static void dmem_byte_set(Vsoc_top_bram_icache *top, int lane, int wi, uint8_t val) {
    Vsoc_top_bram_icache___024root *rootp = top->rootp;
    switch (lane) {
        case 0: M0[wi] = val; break;
        case 1: M1[wi] = val; break;
        case 2: M2[wi] = val; break;
        case 3: M3[wi] = val; break;
    }
}

static void do_reset(Vsoc_top_bram_icache *top, VerilatedVcdC *tfp) {
    RST_N = 0; top->eval();
    for (int i = 0; i < 1024; i++) imem_write(top, i, 0x00000013);
    for (int i = 0; i < 1024; i++) {
        dmem_byte_set(top, 0, i, 0); dmem_byte_set(top, 1, i, 0);
        dmem_byte_set(top, 2, i, 0); dmem_byte_set(top, 3, i, 0);
    }
    for (int i = 1; i < 32; i++) reg_write(top, i, 0);
    for (int i = 0; i < 2; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
    RST_N = 1;
}

static int run_icache_sys(Vsoc_top_bram_icache *top, VerilatedVcdC *tfp) {
    printf("\n=== tb_icache_sys ===\n");
    int pass = 0, fail = 0;

    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS [%s] = 0x%08X\n", msg, got); pass++; }
        else { printf("  FAIL [%s] got=0x%08X expected=0x%08X\n", msg, got, exp); fail++; }
    };

    auto run_cycles = [&](int n) {
        for (int i = 0; i < n; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
    };

    // T1: Cold start sequential fetch
    printf("--- TEST 1: Cold start sequential fetch ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x00A00093); imem_write(top, 1, 0x01400113);
    imem_write(top, 2, 0x01E00193); imem_write(top, 3, 0x02800213);
    run_cycles(60);
    check(1, 10, "T1 cold-start x1=10");
    check(2, 20, "T1 line-hit   x2=20");
    check(3, 30, "T1 line-hit   x3=30");
    check(4, 40, "T1 line-hit   x4=40");

    // T2: Cross cache line with JAL
    printf("--- TEST 2: Cross cache line with JAL ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x00500093); imem_write(top, 1, 0x00000013);
    imem_write(top, 2, 0x00000013); imem_write(top, 3, 0x0080006F);
    imem_write(top, 4, 0x06300193); imem_write(top, 5, 0x00700113);
    imem_write(top, 6, 0x00000013); imem_write(top, 7, 0xFF9FF06F);
    run_cycles(80);
    check(1, 5, "T2 line0       x1=5");
    check(2, 7, "T2 line1-jump  x2=7");
    check(3, 0, "T2 squash      x3=0");

    // T3: Branch to distant address
    printf("--- TEST 3: Branch to distant address ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x00500093); imem_write(top, 1, 0x00500113);
    imem_write(top, 2, 0x02208063);
    for (int i = 3; i <= 9; i++) imem_write(top, i, 0x00000013);
    imem_write(top, 10, 0x02A00213);
    run_cycles(80);
    check(3, 0,  "T3 squash      x3=0");
    check(4, 42, "T3 far-branch  x4=42");

    // T4: Same-index different-tag two-way
    printf("--- TEST 4: Same-index different-tag two-way ---\n");
    do_reset(top, tfp);
    imem_write(top, 0, 0x00100093); imem_write(top, 1, 0x0FC0006F);
    imem_write(top, 2, 0x00000013); imem_write(top, 3, 0x00000013);
    imem_write(top, 64, 0x00200113); imem_write(top, 65, 0x002081B3);
    imem_write(top, 66, 0x00000013); imem_write(top, 67, 0x00000013);
    run_cycles(120);
    check(1, 1, "T4 way0        x1=1");
    check(2, 2, "T4 way1        x2=2");
    check(3, 3, "T4 sum         x3=3");

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
        fprintf(stderr, "Usage: %s +TEST=icache_sys [+WAVE=<path>]\n", argv[0]);
        return 1;
    }

    Vsoc_top_bram_icache *top = new Vsoc_top_bram_icache;
    STALL = 0; FLUSH = 0; EXCEPT = 0; PC_EX = 0; INTR = 0; PC_INTR = 0;

    VerilatedVcdC *tfp = nullptr;
    if (!wave_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(wave_path.c_str());
        printf("Waveform: %s\n", wave_path.c_str());
    }

    int result = (test_name == "icache_sys") ? run_icache_sys(top, tfp) : 1;
    if (tfp) { tfp->close(); delete tfp; }
    top->final();
    delete top;
    return result;
}
