OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.start))
    *(.text*)
    *(.rodata*)
  } > ROM

  .data : {
    *(.data*)
  } > RAM

  .bss (NOLOAD) : {
    *(.bss*)
    *(COMMON)
  } > RAM

  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
