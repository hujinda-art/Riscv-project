// ============================================================================
// tb_l1_cache.cpp — Verilator wrapper for L1_Cache_INST module test
//
// Drives L1_Cache_INST DUT directly (no wrapping testbench).
// Implements backing memory and CPU-side fetch protocol in C++.
// ============================================================================

#include "VL1_Cache_INST.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static uint64_t timestamp = 0;
static const int MEM_WORDS = 32768;
static uint32_t backing[MEM_WORDS];

// Memory-side response control
static bool mem_fast_ready = true;
static bool mem_req_d1 = false;

static uint32_t expected_word(uint32_t byte_addr) {
    uint32_t widx = byte_addr >> 2;
    return ((0x5A ^ (widx & 0xFF)) << 24) | ((widx & 0xFF00) << 8)
           | ((widx & 0xFF0000) >> 8)  | ((widx >> 24) & 0xFF);
}

static void tick(VL1_Cache_INST *top, VerilatedVcdC *tfp) {
    // ---- Memory-side response logic ----
    bool mem_req_cur = top->mem_req;
    if (mem_fast_ready) {
        // Combinational: respond in same cycle
        if (mem_req_cur) {
            uint32_t baddr = top->mem_addr;
            uint32_t widx = baddr >> 2;
            top->mem_rdata = (widx < MEM_WORDS) ? backing[widx] : 0xDEADBEEF;
            top->mem_ready = 1;
        } else {
            top->mem_ready = 0;
        }
    } else {
        // Delayed: respond 1 cycle after mem_req
        if (mem_req_d1) {
            // mem_req was asserted last cycle; respond with latched addr
            top->mem_ready = 1;
            // mem_rdata is set at posedge below
        } else {
            top->mem_ready = 0;
        }
    }

    top->clk = 1;
    top->eval();
    if (tfp) tfp->dump(timestamp++);

    // For slow path: latch rdata at posedge when mem_req is active
    if (!mem_fast_ready && mem_req_cur) {
        uint32_t baddr = top->mem_addr;
        uint32_t widx = baddr >> 2;
        top->mem_rdata = (widx < MEM_WORDS) ? backing[widx] : 0xDEADBEEF;
    }

    top->clk = 0;
    top->eval();
    if (tfp) tfp->dump(timestamp++);

    mem_req_d1 = mem_req_cur;
}

static bool cpu_fetch(VL1_Cache_INST *top, VerilatedVcdC *tfp,
                       uint32_t addr, uint32_t &data, int max_cycles) {
    top->imem_addr = addr;
    top->imem_req = 1;
    top->eval();

    int cyc = 0;
    while (!top->imem_ready && cyc < max_cycles) {
        tick(top, tfp);
        cyc++;
    }

    if (cyc >= max_cycles) {
        printf("TIMEOUT cpu_fetch addr=0x%08X after %d cycles\n", addr, max_cycles);
        top->imem_req = 0;
        data = 0xDEADBEEF;
        tick(top, tfp);
        return false;
    }

    data = top->imem_rdata;
    top->imem_req = 0;
    tick(top, tfp);
    return true;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    std::string wave_path;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg.find("+WAVE=") == 0) wave_path = arg.substr(6);
    }

    printf("\n=== tb_L1_Cache_INST ===\n");

    VL1_Cache_INST *top = new VL1_Cache_INST;

    VerilatedVcdC *tfp = nullptr;
    if (!wave_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(wave_path.c_str());
        printf("Waveform: %s\n", wave_path.c_str());
    }

    int err_count = 0;

    // Initialize backing memory
    for (int k = 0; k < MEM_WORDS; k++)
        backing[k] = expected_word(k << 2);

    top->imem_addr = 0;
    top->imem_req = 0;
    top->mem_rdata = 0;

    // Reset
    top->rst_n = 0;
    for (int i = 0; i < 4; i++) tick(top, tfp);
    top->rst_n = 1;
    for (int i = 0; i < 2; i++) tick(top, tfp);

    // Test 1: Cold miss then hit
    printf("--- 1) Cold start miss -> refill -> hit ---\n");
    {
        uint32_t d0, d1;
        if (cpu_fetch(top, tfp, 0x00000100, d0, 80)) {
            uint32_t exp = expected_word(0x00000100);
            if (d0 == exp) printf("  PASS: cold_line_word0  addr=0x100 data=0x%08X\n", d0);
            else { printf("  FAIL: cold_line_word0  got=0x%08X expected=0x%08X\n", d0, exp); err_count++; }
        } else err_count++;
        if (cpu_fetch(top, tfp, 0x00000100, d1, 20)) {
            uint32_t exp = expected_word(0x00000100);
            if (d1 == exp) printf("  PASS: same_addr_hit  addr=0x100 data=0x%08X\n", d1);
            else { printf("  FAIL: same_addr_hit  got=0x%08X expected=0x%08X\n", d1, exp); err_count++; }
        } else err_count++;
    }

    // Test 2: Same-line hit (different words)
    printf("--- 2) Same line hit ---\n");
    {
        uint32_t dw;
        if (cpu_fetch(top, tfp, 0x00000104, dw, 40)) {
            uint32_t exp = expected_word(0x00000104);
            if (dw == exp) printf("  PASS: same_line_word1  addr=0x104 data=0x%08X\n", dw);
            else { printf("  FAIL: same_line_word1  got=0x%08X expected=0x%08X\n", dw, exp); err_count++; }
        } else err_count++;
        if (cpu_fetch(top, tfp, 0x0000010C, dw, 40)) {
            uint32_t exp = expected_word(0x0000010C);
            if (dw == exp) printf("  PASS: same_line_word3  addr=0x10C data=0x%08X\n", dw);
            else { printf("  FAIL: same_line_word3  got=0x%08X expected=0x%08X\n", dw, exp); err_count++; }
        } else err_count++;
    }

    // Test 3: Same-index different-tag two-way
    printf("--- 3) Same-index different-tag two-way ---\n");
    {
        uint32_t da, db;
        if (cpu_fetch(top, tfp, 0x000000F0, da, 80)) {
            uint32_t exp = expected_word(0x000000F0);
            if (da == exp) printf("  PASS: setA_line  addr=0xF0 data=0x%08X\n", da);
            else { printf("  FAIL: setA_line  got=0x%08X expected=0x%08X\n", da, exp); err_count++; }
        } else err_count++;
        if (cpu_fetch(top, tfp, 0x000100F0, db, 80)) {
            uint32_t exp = expected_word(0x000100F0);
            if (db == exp) printf("  PASS: setB_line  addr=0x100F0 data=0x%08X\n", db);
            else { printf("  FAIL: setB_line  got=0x%08X expected=0x%08X\n", db, exp); err_count++; }
        } else err_count++;
        if (cpu_fetch(top, tfp, 0x000000F0, da, 40)) {
            uint32_t exp = expected_word(0x000000F0);
            if (da == exp) printf("  PASS: setA_hit_after_B  addr=0xF0 data=0x%08X\n", da);
            else { printf("  FAIL: setA_hit_after_B  got=0x%08X expected=0x%08X\n", da, exp); err_count++; }
        } else err_count++;
        if (cpu_fetch(top, tfp, 0x000100F0, db, 40)) {
            uint32_t exp = expected_word(0x000100F0);
            if (db == exp) printf("  PASS: setB_hit_after_A  addr=0x100F0 data=0x%08X\n", db);
            else { printf("  FAIL: setB_hit_after_A  got=0x%08X expected=0x%08X\n", db, exp); err_count++; }
        } else err_count++;
    }

    // Test 4: Slow mem_ready
    printf("--- 4) Slow mem_ready ---\n");
    {
        mem_fast_ready = false;
        mem_req_d1 = false;
        tick(top, tfp);
        uint32_t ds;
        if (cpu_fetch(top, tfp, 0x00000200, ds, 200)) {
            uint32_t exp = expected_word(0x00000200);
            if (ds == exp) printf("  PASS: slow_mem_line  addr=0x200 data=0x%08X\n", ds);
            else { printf("  FAIL: slow_mem_line  got=0x%08X expected=0x%08X\n", ds, exp); err_count++; }
        } else err_count++;
        mem_fast_ready = true;
        mem_req_d1 = false;
        tick(top, tfp);
    }

    printf("\nRESULT: %s  errors=%d\n", (err_count == 0) ? "ALL PASS" : "FAIL", err_count);

    if (tfp) { tfp->close(); delete tfp; }
    top->final();
    delete top;
    return (err_count > 0) ? 1 : 0;
}
