.section .text
    .globl _start

_start:
    addi x10, x0, 0
    addi x5,  x0, 63

loop:
    addi x10, x10, 1
    and  x10, x10, x5

delay:
    lui  x6, 0x100
    # addi x6, x0, 5 # simülasyon için

delay_loop:
    addi x6, x6, -1
    bne  x6, x0, delay_loop

    jal x0, loop
