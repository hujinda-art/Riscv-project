// ============================================================================
// tb_soc_top_bram.cpp — Verilator C++ wrapper for soc_top_bram DUT tests
//
// Covers 6 testbenches:
//   +TEST=system           → tb_system_soc (full_instr.hex, 18 signatures)
//   +TEST=fwd               → tb_fwd_hazard (tb_fwd.hex, SIG[14]==1)
//   +TEST=mem               → tb_mem_loadstore (tb_mem.hex, SIG[17]==0x11223344)
//   +TEST=core_jump         → core_jump_tb (hardcoded JAL test)
//   +TEST=jump_no_mem       → tb_jump_no_mem (6 sub-tests)
//   +TEST=special_features  → special_features_tb (7 sub-tests)
//
// Usage:
//   ./Vsoc_top_bram +TEST=system +HEX=path/to/full_instr.hex +WAVE=out.vcd
// ============================================================================

#include "Vsoc_top_bram.h"
#include "Vsoc_top_bram___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <fstream>
#include <sstream>
#include <vector>

using std::string;
using std::vector;
using std::ifstream;
using std::istringstream;

// ============================================================================
// Helpers: read hex file
// ============================================================================
static vector<uint32_t> read_hex(const char *path) {
    vector<uint32_t> words;
    ifstream f(path);
    if (!f.is_open()) {
        fprintf(stderr, "ERROR: cannot open hex file: %s\n", path);
        return words;
    }
    string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        istringstream iss(line);
        string tok;
        if (iss >> tok) {
            uint32_t w = std::stoul(tok, nullptr, 16);
            words.push_back(w);
        }
    }
    return words;
}

// ============================================================================
// Convenience wrappers for internal signal access
// All internal signals go through rootp (Verilator 5.x pattern)
// ============================================================================

// Ports (direct access)
#define CLK      top->clk
#define RST_N    top->rst_n
#define STALL    top->stall
#define FLUSH    top->flush
#define EXCEPT   top->exception
#define PC_EX    top->pc_exception
#define INTR     top->__SYM__interrupt
#define PC_INTR  top->pc_interrupt

// Internal signals (via rootp)
#define R rootp
#define DMEM_VALID   R->soc_top_bram__DOT__dmem_valid
#define DMEM_WEN     R->soc_top_bram__DOT__dmem_wen
#define DMEM_ADDR    R->soc_top_bram__DOT__dmem_addr
#define DMEM_WDATA   R->soc_top_bram__DOT__dmem_wdata
#define IMEM_MEM     R->soc_top_bram__DOT__u_inst_mem__DOT__mem
#define DMEM_MEM0    R->soc_top_bram__DOT__u_data_mem__DOT__mem0
#define DMEM_MEM1    R->soc_top_bram__DOT__u_data_mem__DOT__mem1
#define DMEM_MEM2    R->soc_top_bram__DOT__u_data_mem__DOT__mem2
#define DMEM_MEM3    R->soc_top_bram__DOT__u_data_mem__DOT__mem3
#define REGS         R->soc_top_bram__DOT__u_core__DOT__u_regfile__DOT__regs

// ============================================================================
static uint64_t timestamp = 0;

static void tick(Vsoc_top_bram *top, VerilatedVcdC *tfp, bool clk_val) {
    CLK = clk_val;
    top->eval();
    if (tfp) { tfp->dump(timestamp); timestamp += 5; }
}

static uint32_t dmem_read_word(Vsoc_top_bram *top, int wi) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    return (uint32_t(DMEM_MEM3[wi]) << 24)
         | (uint32_t(DMEM_MEM2[wi]) << 16)
         | (uint32_t(DMEM_MEM1[wi]) << 8)
         | (uint32_t(DMEM_MEM0[wi]));
}

static void dmem_write_word(Vsoc_top_bram *top, int wi, uint32_t val) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    DMEM_MEM0[wi] = val & 0xFF;
    DMEM_MEM1[wi] = (val >> 8) & 0xFF;
    DMEM_MEM2[wi] = (val >> 16) & 0xFF;
    DMEM_MEM3[wi] = (val >> 24) & 0xFF;
}

static uint32_t reg_read(Vsoc_top_bram *top, int i) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    return REGS[i];
}

static void reg_write(Vsoc_top_bram *top, int i, uint32_t val) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    REGS[i] = val;
}

static void imem_write(Vsoc_top_bram *top, int idx, uint32_t val) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    IMEM_MEM[idx] = val;
}

static uint32_t imem_read(Vsoc_top_bram *top, int idx) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    return IMEM_MEM[idx];
}

static bool check_done_write(Vsoc_top_bram *top) {
    Vsoc_top_bram___024root *rootp = top->rootp;
    return DMEM_VALID && DMEM_WEN
        && (DMEM_ADDR == 0x00000080)
        && (DMEM_WDATA == 0xC001D00D);
}

static void reset_dut(Vsoc_top_bram *top, VerilatedVcdC *tfp, int hold_cycles) {
    RST_N = 0;
    STALL = 0; FLUSH = 0;
    EXCEPT = 0; PC_EX = 0;
    INTR = 0; PC_INTR = 0;
    for (int i = 0; i < hold_cycles; i++) {
        tick(top, tfp, 1);
        tick(top, tfp, 0);
    }
    RST_N = 1;
}

// ============================================================================
// Hex-file-based tests
// ============================================================================
static int run_hex_test(Vsoc_top_bram *top, VerilatedVcdC *tfp,
                         const char *hex_path, const char *test_name,
                         int max_cycles,
                         const vector<int> &sig_indices,
                         const vector<uint32_t> &sig_expected,
                         const vector<string> &sig_names,
                         bool check_imem_fp, uint32_t fp_addr, uint32_t fp_val) {
    printf("\n=== %s ===\n", test_name);

    auto hex = read_hex(hex_path);
    if (hex.empty()) {
        printf("FAIL: cannot load hex file %s\n", hex_path);
        return 1;
    }
    printf("Loaded %zu words from %s\n", hex.size(), hex_path);

    RST_N = 0;
    STALL = 0; FLUSH = 0;
    EXCEPT = 0; PC_EX = 0;
    INTR = 0; PC_INTR = 0;
    top->eval();

    for (size_t i = 0; i < hex.size(); i++)
        imem_write(top, i, hex[i]);

    for (int i = 0; i < 1024; i++)
        dmem_write_word(top, i, 0);

    if (check_imem_fp) {
        uint32_t val = imem_read(top, fp_addr >> 2);
        if (val != fp_val) {
            printf("TB-ERROR: IMEM[%d] = 0x%08X, expected 0x%08X\n",
                   fp_addr >> 2, val, fp_val);
        } else {
            printf("IMEM fingerprint OK at word %u\n", fp_addr >> 2);
        }
    }

    reset_dut(top, tfp, 5);

    int cycle = 0;
    bool done = false;
    while (!done && cycle < max_cycles) {
        tick(top, tfp, 1);
        if (check_done_write(top)) done = true;
        tick(top, tfp, 0);
        if (!done) cycle++;
    }

    int pass = 0, fail = 0;
    if (!done) {
        printf("TIMEOUT after %d cycles — DONE_MAGIC not seen at 0x80\n", cycle);
        printf("DBG: id_pc=0x%08X ex_pc_out=0x%08X\n", top->id_pc, top->ex_pc_out);
        fail++;
    } else {
        printf("DONE seen at cycle %d\n", cycle);
        for (size_t i = 0; i < sig_indices.size(); i++) {
            int wi = (0x100 >> 2) + sig_indices[i];
            uint32_t got = dmem_read_word(top, wi);
            uint32_t exp = sig_expected[i];
            if (got == exp) {
                printf("  PASS [%-24s] = 0x%08X\n", sig_names[i].c_str(), got);
                pass++;
            } else {
                printf("  FAIL [%-24s] got=0x%08X expected=0x%08X\n",
                       sig_names[i].c_str(), got, exp);
                fail++;
            }
        }
    }
    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    return (fail > 0) ? 1 : 0;
}

// ============================================================================
// Hardcoded-program tests
// ============================================================================

static int run_core_jump(Vsoc_top_bram *top, VerilatedVcdC *tfp) {
    printf("\n=== core_jump_tb ===\n");

    RST_N = 0; STALL = 0; FLUSH = 0;
    EXCEPT = 0; PC_EX = 0; INTR = 0; PC_INTR = 0;
    top->eval();

    imem_write(top, 0, 0x00100113); // addi x2, x0, 1
    imem_write(top, 1, 0x0080006F); // jal  x0, +8
    imem_write(top, 2, 0x00700193); // addi x3, x0, 7  [SQUASH]
    imem_write(top, 3, 0x00900213); // addi x4, x0, 9  [TARGET]
    for (int i = 4; i < 8; i++) imem_write(top, i, 0x00000013);

    reset_dut(top, tfp, 10);
    for (int i = 0; i < 60; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }

    int pass = 0, fail = 0;
    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS: %s reg[%d]=%u\n", msg, r, got); pass++; }
        else { printf("  FAIL: %s reg[%d]=%u (expected %u)\n", msg, r, got, exp); fail++; }
    };
    check(2, 1, "x2 addi");
    check(3, 0, "x3 squash");
    check(4, 9, "x4 target");
    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    return (fail > 0) ? 1 : 0;
}

static int run_jump_no_mem(Vsoc_top_bram *top, VerilatedVcdC *tfp) {
    printf("\n=== tb_jump_no_mem ===\n");

    RST_N = 0; STALL = 0; FLUSH = 0;
    EXCEPT = 0; PC_EX = 0; INTR = 0; PC_INTR = 0;
    top->eval();

    // T1
    imem_write(top, 0,  0x00500093); imem_write(top, 1,  0x0080016F);
    imem_write(top, 2,  0x06300193); imem_write(top, 3,  0x00700213);
    // T2
    imem_write(top, 4,  0x02400293); imem_write(top, 5,  0x00028367);
    imem_write(top, 6,  0x06300393); imem_write(top, 7,  0x00000013);
    imem_write(top, 8,  0x00000013); imem_write(top, 9,  0x00900413);
    // T3
    imem_write(top, 10, 0x00A00493); imem_write(top, 11, 0x00A00513);
    imem_write(top, 12, 0x00528663); imem_write(top, 13, 0x06300593);
    imem_write(top, 14, 0x06200593); imem_write(top, 15, 0x00B00613);
    // T4
    imem_write(top, 16, 0x00A49463); imem_write(top, 17, 0x00D00693);
    imem_write(top, 18, 0x00000013); imem_write(top, 19, 0x00E00713);
    // T5
    imem_write(top, 20, 0x00500793); imem_write(top, 21, 0x0097C463);
    imem_write(top, 22, 0x06300813); imem_write(top, 23, 0x01100893);
    // T6
    imem_write(top, 24, 0x00000913); imem_write(top, 25, 0x00190913);
    imem_write(top, 26, 0x00300993); imem_write(top, 27, 0xFF394CE3);
    imem_write(top, 28, 0x01400A13); imem_write(top, 29, 0x0000006F);

    reset_dut(top, tfp, 10);
    for (int i = 0; i < 150; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }

    int pass = 0, fail = 0;
    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS: %s reg[%d]=%u\n", msg, r, got); pass++; }
        else { printf("  FAIL: %s reg[%d]=%u (expected %u)\n", msg, r, got, exp); fail++; }
    };
    check(1,  5,    "T1 addi x1=5");     check(2,  0x08, "T1 jal  x2 link=8");
    check(3,  0,    "T1 squash x3");     check(4,  7,    "T1 target x4=7");
    check(5,  0x24, "T2 x5=0x24");       check(6,  0x18, "T2 jalr x6=0x18");
    check(7,  0,    "T2 squash x7");     check(8,  9,    "T2 target x8=9");
    check(9,  10,   "T3 x9=10");         check(10, 10,   "T3 x10=10");
    check(11, 0,    "T3 squash x11");    check(12, 11,   "T3 target x12=11");
    check(13, 13,   "T4 x13=13");        check(14, 14,   "T4 x14=14");
    check(15, 5,    "T5 x15=5");         check(16, 0,    "T5 squash x16");
    check(17, 17,   "T5 target x17=17"); check(18, 3,    "T6 loop x18=3");
    check(19, 3,    "T6 x19=3");         check(20, 20,   "T6 x20=20");
    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    return (fail > 0) ? 1 : 0;
}

static int run_special_features(Vsoc_top_bram *top, VerilatedVcdC *tfp) {
    printf("\n=== special_features_tb ===\n");
    int pass = 0, fail = 0;

    auto check = [&](int r, uint32_t exp, const char *msg) {
        uint32_t got = reg_read(top, r);
        if (got == exp) { printf("  PASS [%s] = 0x%08X\n", msg, got); pass++; }
        else { printf("  FAIL [%s] got=0x%08X expected=0x%08X\n", msg, got, exp); fail++; }
    };

    auto do_reset = [&]() {
        RST_N = 0; top->eval();
        for (int i = 0; i < 1024; i++) imem_write(top, i, 0x00000013);
        for (int i = 0; i < 1024; i++) dmem_write_word(top, i, 0);
        for (int i = 1; i < 32; i++) reg_write(top, i, 0);
        for (int i = 0; i < 2; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
        RST_N = 1;
    };

    auto run_cycles = [&](int n) {
        for (int i = 0; i < n; i++) { tick(top, tfp, 1); tick(top, tfp, 0); }
    };

    // T1: Early JAL in IF/ID
    printf("--- TEST 1: Early JAL in IF/ID + rd = PC+4 ---\n");
    do_reset();
    imem_write(top, 0, 0x00500093); imem_write(top, 1, 0x0080016F);
    imem_write(top, 2, 0x06300193); imem_write(top, 3, 0x00700213);
    run_cycles(40);
    check(1, 5,    "T1 addi    x1=5");          check(2, 0x08, "T1 JAL-lnk x2=0x08(PC+4)");
    check(3, 0,    "T1 squash  x3=0");          check(4, 7,    "T1 target  x4=7");

    // T2: JALR rd = PC+4
    printf("--- TEST 2: JALR rd = PC+4 ---\n");
    do_reset();
    imem_write(top, 0, 0x00C00093); imem_write(top, 1, 0x00008167);
    imem_write(top, 2, 0x06300293); imem_write(top, 3, 0x00700193);
    run_cycles(40);
    check(2, 0x08, "T2 JALR-lnk x2=0x08");      check(3, 7,    "T2 target   x3=7");
    check(5, 0,    "T2 squash   x5=0");

    // T3: Load-use hazard
    printf("--- TEST 3: Load-use hazard ---\n");
    do_reset();
    imem_write(top, 0, 0x06400093); imem_write(top, 1, 0x00102023);
    imem_write(top, 2, 0x00000013); imem_write(top, 3, 0x00002103);
    imem_write(top, 4, 0x00110193); imem_write(top, 5, 0x00018213);
    run_cycles(20);
    check(2, 100, "T3 lw        x2=100");        check(3, 101, "T3 load-use  x3=101");
    check(4, 101, "T3 chain-fwd x4=101");

    // T4: Consecutive ALU forwarding
    printf("--- TEST 4: Consecutive ALU forwarding ---\n");
    do_reset();
    imem_write(top, 0, 0x00A00093); imem_write(top, 1, 0x00508113);
    imem_write(top, 2, 0x001101B3); imem_write(top, 3, 0x00218233);
    run_cycles(40);
    check(1, 10, "T4 x1=10"); check(2, 15, "T4 x2=15");
    check(3, 25, "T4 x3=25"); check(4, 40, "T4 x4=40");

    // T5: Dual WB paths
    printf("--- TEST 5: Dual WB paths ---\n");
    do_reset();
    imem_write(top, 0, 0x02A00093); imem_write(top, 1, 0x00102023);
    imem_write(top, 2, 0x00000013); imem_write(top, 3, 0x00000013);
    imem_write(top, 4, 0x00002103);
    imem_write(top, 5, 0x00000013); imem_write(top, 6, 0x00000013);
    imem_write(top, 7, 0x00000013); imem_write(top, 8, 0x002081B3);
    run_cycles(60);
    check(1, 42, "T5 EX_WB  x1=42"); check(2, 42, "T5 MEM_WB x2=42");
    check(3, 84, "T5 sum    x3=84");

    // T6: Branch flush scope
    printf("--- TEST 6: Branch flush scope ---\n");
    do_reset();
    imem_write(top, 0, 0x00500093); imem_write(top, 1, 0x00500113);
    imem_write(top, 2, 0x00208663); imem_write(top, 3, 0x06300193);
    imem_write(top, 4, 0x06200193); imem_write(top, 5, 0x00700213);
    run_cycles(40);
    check(3, 0, "T6 squash x3=0"); check(4, 7, "T6 target x4=7");

    // T7: JAL port-2 overrides WB port-1
    printf("--- TEST 7: JAL port-2 overrides WB port-1 ---\n");
    do_reset();
    imem_write(top, 0, 0x06300093); imem_write(top, 1, 0x00000013);
    imem_write(top, 2, 0x008000EF); imem_write(top, 3, 0x03700293);
    imem_write(top, 4, 0x00100113);
    run_cycles(40);
    check(1, 0x0C, "T7 JAL-lnk x1=0x0C"); check(5, 0, "T7 squash  x5=0");
    check(2, 1,    "T7 target  x2=1");

    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);
    return (fail > 0) ? 1 : 0;
}

// ============================================================================
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    string test_name, hex_path, wave_path;
    for (int i = 1; i < argc; i++) {
        string arg = argv[i];
        if (arg.find("+TEST=") == 0)      test_name = arg.substr(6);
        else if (arg.find("+HEX=") == 0)  hex_path  = arg.substr(5);
        else if (arg.find("+WAVE=") == 0) wave_path = arg.substr(6);
    }

    if (test_name.empty()) {
        fprintf(stderr, "Usage: %s +TEST=<test> [+HEX=<path>] [+WAVE=<path>]\n", argv[0]);
        fprintf(stderr, "Tests: system, fwd, mem, core_jump, jump_no_mem, special_features\n");
        return 1;
    }

    Vsoc_top_bram *top = new Vsoc_top_bram;

    VerilatedVcdC *tfp = nullptr;
    if (!wave_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(wave_path.c_str());
        printf("Waveform: %s\n", wave_path.c_str());
    }

    int result = 0;
    if (test_name == "system") {
        if (hex_path.empty()) hex_path = "../../scripts/sw/build/full_instr.hex";
        result = run_hex_test(top, tfp, hex_path.c_str(), "tb_system_soc",
                              50000,
                              {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17},
                              {13,7,2,11,9,12,4,0xFFFFFFFC,1,1,
                               42,0x12345000,4,1,1,1,1,0x11223344},
                              {"ADD","SUB","AND","OR","XOR","SLL","SRL","SRA",
                               "SLT","SLTU","MUL","LUI","AUIPC_REL","BEQ/BNE",
                               "BLT","JAL","JALR","LW/SW"},
                              true, 0, 0x00001117);
    } else if (test_name == "fwd") {
        if (hex_path.empty()) hex_path = "../../scripts/sw/build/tb_fwd.hex";
        result = run_hex_test(top, tfp, hex_path.c_str(), "tb_fwd_hazard",
                              100000, {14}, {1}, {"SIG[14]=1"},
                              true, 0x10, 0xFFF00293);
    } else if (test_name == "mem") {
        if (hex_path.empty()) hex_path = "../../scripts/sw/build/tb_mem.hex";
        result = run_hex_test(top, tfp, hex_path.c_str(), "tb_mem_loadstore",
                              100000, {17}, {0x11223344}, {"SIG[17]=0x11223344"},
                              false, 0, 0);
    } else if (test_name == "core_jump") {
        result = run_core_jump(top, tfp);
    } else if (test_name == "jump_no_mem") {
        result = run_jump_no_mem(top, tfp);
    } else if (test_name == "special_features") {
        result = run_special_features(top, tfp);
    } else {
        fprintf(stderr, "Unknown test: %s\n", test_name.c_str());
        result = 1;
    }

    if (tfp) { tfp->close(); delete tfp; }
    top->final();
    delete top;
    return result;
}
