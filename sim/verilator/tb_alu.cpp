// ============================================================================
// tb_alu.cpp — Verilator wrapper for ALU module test
// ============================================================================

#include "VALU.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    std::string wave_path;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg.find("+WAVE=") == 0) wave_path = arg.substr(6);
    }

    printf("\n=== ALU_test ===\n");

    VALU *top = new VALU;

    VerilatedVcdC *tfp = nullptr;
    if (!wave_path.empty()) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(wave_path.c_str());
        printf("Waveform: %s\n", wave_path.c_str());
    }

    int pass = 0, fail = 0;
    uint64_t ts = 0;

    auto eval = [&]() {
        top->eval();
        if (tfp) tfp->dump(ts);
        ts += 5;
    };

    auto test_one = [&](uint32_t a, uint32_t b, uint8_t op,
                         uint32_t exp_result, const char *desc) {
        top->a = a;
        top->b = b;
        top->op = op;
        eval();
        uint32_t got = top->result;
        if (got == exp_result) {
            printf("  PASS: %s  %u op %u = %u\n", desc, a, b, got);
            pass++;
        } else {
            printf("  FAIL: %s  got=%u expected=%u\n", desc, got, exp_result);
            fail++;
        }
    };

    // Op encoding: 0=ADD, 1=SUB, 2=MUL
    test_one(5, 3, 0, 8,  "5+3=8");
    test_one(0xFFFFFFFF, 1, 0, 0, "0xFFFFFFFF+1=0");
    test_one(5, 3, 1, 2,  "5-3=2");
    test_one(5, 3, 2, 15, "5*3=15");

    printf("RESULT: PASS=%d FAIL=%d\n", pass, fail);

    if (tfp) { tfp->close(); delete tfp; }
    top->final();
    delete top;
    return (fail > 0) ? 1 : 0;
}
