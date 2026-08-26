.section .text
    .globl _start
_start:
    lui  x6, 0x10000          # x6 = 0x10000000 (gpio base)

    addi x8, x0, 0x3F         # pins 0-5 (LEDs) = output, rest = input
    sw   x8, 0x00(x6)         # DIR_LO

    addi x10, x0, 0           # x10 = sayac
    addi x5,  x0, 63          # x5 = maske (6 bit)

wait_press:
    lw   x7, 0x10(x6)         # IN_LO
    andi x7, x7, 0x40         # bit6 = S2 button
    beq  x7, x0, wait_press

    addi x10, x10, 1
    and  x10, x10, x5
    sw   x10, 0x08(x6)        # OUT_LO

wait_release:
    lw   x7, 0x10(x6)
    andi x7, x7, 0x40
    bne  x7, x0, wait_release

    jal  x0, wait_press
