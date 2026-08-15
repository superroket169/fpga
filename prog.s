.section .text
    .globl _start
_start:
    addi x10, x0, 0          # x10 = sayac
    addi x5,  x0, 63         # x5 = maske (6 bit)
    lui  x6,  0x1A000        # x6 = 0x1A000000 (buton+led bloğunun tabani)

wait_press:
    lw   x7, 4(x6)
    andi x7, x7, 1
    beq  x7, x0, wait_press 

    addi x10, x10, 1
    and  x10, x10, x5
    sw   x10, 0(x6)

wait_release:
    lw   x7, 4(x6)
    andi x7, x7, 1
    bne  x7, x0, wait_release

    jal  x0, wait_press
