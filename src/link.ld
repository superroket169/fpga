/* Minimal linker script for both scripts/c_compiler.sh and
 * scripts/program_translater.sh
 * ORIGIN_ADDR is passed in via --defsym
 * (0x0 for the bootloader image, 0x400 for a program meant to be loaded through it).
 *
 * Note: .bss is NOT zero-filled at startup - there's no crt0 doing that
 * yet, so don't rely on uninitialized globals reading as zero.
 */

ENTRY(_reset)

SECTIONS
{
    . = ORIGIN_ADDR;

    .text : {
        *(.text.entry)
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    }

    .bss : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.comment)
        *(.riscv.attributes)
    }
}
