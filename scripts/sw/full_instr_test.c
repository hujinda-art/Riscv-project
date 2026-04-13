#include <stdint.h>

#define SIG_BASE_ADDR   0x00000100u
#define DONE_ADDR       0x00000080u
#define DONE_MAGIC      0xC001D00Du

static volatile uint32_t *const sig  = (volatile uint32_t *)SIG_BASE_ADDR;
static volatile uint32_t *const done = (volatile uint32_t *)DONE_ADDR;

static inline void emit_sig(uint32_t idx, uint32_t value) {
    sig[idx] = value;
}

static uint32_t test_jal(void) {
    uint32_t pass;
    asm volatile(
        "li t0, 0\n"
        "jal t1, 1f\n"
        "li t0, 0xdeadbeef\n"
        "1:\n"
        "andi t2, t1, 3\n"
        "sltiu t2, t2, 1\n"
        "sltu t3, x0, t1\n"
        "and %0, t2, t3\n"
        : "=r"(pass)
        :
        : "t0", "t1", "t2", "t3"
    );
    return pass;
}

static uint32_t test_jalr(void) {
    uint32_t pass;
    asm volatile(
        "li t2, 0\n"
        "la t0, 1f\n"
        "jalr t1, t0, 0\n"
        "li t2, 0xdeadbeef\n"
        "1:\n"
        "andi t3, t1, 3\n"
        "sltiu t3, t3, 1\n"
        "sltu t4, x0, t1\n"
        "and %0, t3, t4\n"
        : "=r"(pass)
        :
        : "t0", "t1", "t2", "t3", "t4"
    );
    return pass;
}

int main(void) {
    uint32_t r;
    volatile uint32_t *mem = (volatile uint32_t *)0x00000200u;

    asm volatile("li t0, 10\nli t1, 3\nadd %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(0, r);

    asm volatile("li t0, 10\nli t1, 3\nsub %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(1, r);

    asm volatile("li t0, 10\nli t1, 3\nand %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(2, r);

    asm volatile("li t0, 10\nli t1, 3\nor %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(3, r);

    asm volatile("li t0, 10\nli t1, 3\nxor %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(4, r);

    asm volatile("li t0, 3\nli t1, 2\nsll %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(5, r);

    asm volatile("li t0, 16\nli t1, 2\nsrl %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(6, r);

    asm volatile("li t0, -16\nli t1, 2\nsra %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(7, r);

    asm volatile("li t0, -1\nli t1, 1\nslt %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(8, r);

    asm volatile("li t0, 1\nli t1, 2\nsltu %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(9, r);

    asm volatile("li t0, 7\nli t1, 6\nmul %0, t0, t1" : "=r"(r) : : "t0", "t1");
    emit_sig(10, r);

    asm volatile("lui %0, 0x12345" : "=r"(r));
    emit_sig(11, r);

    asm volatile(
        "auipc t0, 0\n"
        "auipc t1, 0\n"
        "sub %0, t1, t0\n"
        : "=r"(r)
        :
        : "t0", "t1"
    );
    emit_sig(12, r);

    asm volatile(
        "li t0, 5\n"
        "li t1, 5\n"
        "li %0, 0\n"
        "bne t0, t1, 1f\n"
        "addi %0, %0, 1\n"
        "1:\n"
        : "=&r"(r)
        :
        : "t0", "t1"
    );
    emit_sig(13, r);

    asm volatile(
        "li t0, -1\n"
        "li t1, 1\n"
        "li %0, 0\n"
        "blt t0, t1, 1f\n"
        "jal x0, 2f\n"
        "1: li %0, 1\n"
        "2:\n"
        : "=&r"(r)
        :
        : "t0", "t1"
    );
    emit_sig(14, r);

    emit_sig(15, test_jal());
    emit_sig(16, test_jalr());

    mem[0] = 0x11223344u;
    asm volatile("lw %0, 0(%1)" : "=r"(r) : "r"(mem));
    emit_sig(17, r);

    *done = DONE_MAGIC;

    asm volatile(
        "1:\n"
        "jal x0, 1b\n"
    );

    return 0;
}
