/*
 * matmul_test.c — 4x4 矩阵乘法验证程序
 *
 * 计算 C = A * B，与预期结果比对，通过 UART 输出 PASS/FAIL。
 * 不依赖 M 扩展，乘法由 libgcc 软件实现。
 * 所有数组分配在栈上、运行时初始化，无需 .data 段 / DMEM 预初始化。
 *
 * 构建: cd scripts/sw && make matmul
 * UART: 0x10001000，软件延迟确保 115200/230400 baud 不丢字符
 */

#define N 4

volatile unsigned int  *const uart_status = (volatile unsigned int  *)0x10001000u;
volatile unsigned char *const uart_tx     = (volatile unsigned char *)0x10001000u;

static void uart_putc(char c)
{
    for (volatile int i = 0; i < 5000; i++)
        __asm__ volatile ("nop");
    *uart_tx = c;
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

static void print_int(int n)
{
    char buf[12];
    int i = 0;
    if (n == 0) {
        uart_putc('0');
        return;
    }
    if (n < 0) {
        uart_putc('-');
        n = -n;
    }
    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    while (i > 0)
        uart_putc(buf[--i]);
}

static void print_matrix(int m[N][N])
{
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            print_int(m[i][j]);
            uart_putc(' ');
        }
        uart_puts("\r\n");
    }
}

void main(void)
{
    /* 所有数组分配在栈上，运行时初始化 — 无需 DMEM 预加载 */
    int A[N][N];
    int B[N][N];
    int C[N][N];
    int C_exp[N][N];

    /* A = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]] */
    A[0][0]=1;  A[0][1]=2;  A[0][2]=3;  A[0][3]=4;
    A[1][0]=5;  A[1][1]=6;  A[1][2]=7;  A[1][3]=8;
    A[2][0]=9;  A[2][1]=10; A[2][2]=11; A[2][3]=12;
    A[3][0]=13; A[3][1]=14; A[3][2]=15; A[3][3]=16;

    /* B = [[17,18,19,20],[21,22,23,24],[25,26,27,28],[29,30,31,32]] */
    B[0][0]=17; B[0][1]=18; B[0][2]=19; B[0][3]=20;
    B[1][0]=21; B[1][1]=22; B[1][2]=23; B[1][3]=24;
    B[2][0]=25; B[2][1]=26; B[2][2]=27; B[2][3]=28;
    B[3][0]=29; B[3][1]=30; B[3][2]=31; B[3][3]=32;

    /* C_exp = 预期结果 = A * B 手算值 */
    C_exp[0][0]=250;  C_exp[0][1]=260;  C_exp[0][2]=270;  C_exp[0][3]=280;
    C_exp[1][0]=618;  C_exp[1][1]=644;  C_exp[1][2]=670;  C_exp[1][3]=696;
    C_exp[2][0]=986;  C_exp[2][1]=1028; C_exp[2][2]=1070; C_exp[2][3]=1112;
    C_exp[3][0]=1354; C_exp[3][1]=1412; C_exp[3][2]=1470; C_exp[3][3]=1528;

    /* 矩阵乘法 C = A * B */
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            int sum = 0;
            for (int k = 0; k < N; k++)
                sum += A[i][k] * B[k][j];
            C[i][j] = sum;
        }

    /* 比对结果 */
    int pass = 1;
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            if (C[i][j] != C_exp[i][j])
                pass = 0;

    /* UART 输出 */
    uart_puts("\r\n=== Matrix Multiply Test ===\r\n");
    uart_puts("A =\r\n"); print_matrix(A);
    uart_puts("B =\r\n"); print_matrix(B);
    uart_puts("C = A*B =\r\n"); print_matrix(C);
    uart_puts("Expected =\r\n"); print_matrix(C_exp);

    if (pass)
        uart_puts("\r\n*** PASS ***\r\n");
    else
        uart_puts("\r\n*** FAIL ***\r\n");

    for (;;)
        __asm__ volatile ("nop");
}
