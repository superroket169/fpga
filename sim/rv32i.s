# RV32I self-check for sim/testbench.v. Each test leaves its number in x31;
# a mismatch jumps to `fail`, which reports it through TOHOST.
#
# lui/addi/bne come first because every later check is built from li + bne.
#
# Run: scripts/sim.sh sim/rv32i.s

.equ TOHOST, 0xF0000000

# rd = a <inst> b
.macro TEST_RR num, inst, exp, a, b
    li   x31, \num
    li   x1, \a
    li   x2, \b
    \inst x3, x1, x2
    li   x4, \exp
    bne  x3, x4, fail
.endm

# rd = a <inst> imm
.macro TEST_RI num, inst, exp, a, imm
    li   x31, \num
    li   x1, \a
    \inst x3, x1, \imm
    li   x4, \exp
    bne  x3, x4, fail
.endm

.macro TEST_BR_TAKEN num, inst, a, b
    li   x31, \num
    li   x1, \a
    li   x2, \b
    \inst x1, x2, 1f
    j    fail
1:
.endm

.macro TEST_BR_NOT num, inst, a, b
    li   x31, \num
    li   x1, \a
    li   x2, \b
    \inst x1, x2, fail
.endm

# rd = mem[base + off]
.macro TEST_LD num, inst, exp, off, base
    li   x31, \num
    la   x5, \base
    \inst x3, \off(x5)
    li   x4, \exp
    bne  x3, x4, fail
.endm

# store val with <st>, read it back with <ld>
.macro TEST_ST num, st, ld, exp, val, off
    li   x31, \num
    la   x5, sbuf
    li   x1, \val
    \st  x1, \off(x5)
    \ld  x3, \off(x5)
    li   x4, \exp
    bne  x3, x4, fail
.endm

.section .text.entry
.globl _reset
_reset:
    # ---- bootstrap: lui, addi, bne, beq ----
    li   x31, 1
    lui  x1, 0x12345
    addi x1, x1, 0x678
    lui  x2, 0x12345
    ori  x2, x2, 0x678
    bne  x1, x2, fail
    beq  x1, x2, 1f
    j    fail
1:

    # ---- x0 stays zero ----
    li   x31, 2
    addi x0, x0, 5
    bne  x0, zero, fail
    li   x4, 0
    bne  x0, x4, fail

    # ---- R-type ----
    TEST_RR 10, add,  0x00000003, 1, 2
    TEST_RR 11, add,  0x00000000, -1, 1
    TEST_RR 12, add,  0x80000000, 0x7FFFFFFF, 1
    TEST_RR 13, sub,  0xFFFFFFFF, 1, 2
    TEST_RR 14, sub,  0x7FFFFFFF, 0x80000000, 1
    TEST_RR 15, and,  0x0F000F00, 0xFF00FF00, 0x0F0F0F0F
    TEST_RR 16, or,   0xFF0FFF0F, 0xFF00FF00, 0x0F0F0F0F
    TEST_RR 17, xor,  0xF00FF00F, 0xFF00FF00, 0x0F0F0F0F
    TEST_RR 18, sll,  0x80000000, 1, 31
    TEST_RR 19, sll,  0x00000002, 1, 33          # only rs2[4:0] counts
    TEST_RR 20, srl,  0x08000000, 0x80000000, 4
    TEST_RR 21, sra,  0xF8000000, 0x80000000, 4
    TEST_RR 22, sra,  0x07000000, 0x70000000, 4
    TEST_RR 23, slt,  1, -1, 1
    TEST_RR 24, slt,  0, 1, -1
    TEST_RR 25, slt,  0, 5, 5
    TEST_RR 26, sltu, 0, -1, 1
    TEST_RR 27, sltu, 1, 1, -1

    # ---- I-type ALU ----
    TEST_RI 30, addi,  0x00000000, 1, -1
    TEST_RI 31, addi,  0x000007FF, 0, 2047
    TEST_RI 32, addi,  0xFFFFF800, 0, -2048
    TEST_RI 33, andi,  0x00000700, 0xFF00FF00, 0x70F   # positive imm, upper bits 0
    TEST_RI 34, andi,  0xFF00FF00, 0xFF00FF00, -1      # sign-extended imm
    TEST_RI 35, ori,   0xFF00FFFF, 0xFF00FF00, 0xFF
    TEST_RI 36, xori,  0x00FF00FF, 0xFF00FF00, -1
    TEST_RI 37, slti,  1, -5, -4
    TEST_RI 38, slti,  0, -4, -5
    TEST_RI 39, sltiu, 1, 0, -1                        # 0 < 0xFFFFFFFF
    TEST_RI 40, sltiu, 0, -1, 1
    TEST_RI 41, slli,  0x80000000, 1, 31
    TEST_RI 42, srli,  0x00000001, 0x80000000, 31
    TEST_RI 43, srai,  0xFFFFFFFF, 0x80000000, 31
    TEST_RI 44, srai,  0x00000001, 0x40000000, 30

    # ---- branches ----
    TEST_BR_TAKEN 50, beq,  7, 7
    TEST_BR_NOT   51, beq,  7, 8
    TEST_BR_TAKEN 52, bne,  7, 8
    TEST_BR_NOT   53, bne,  7, 7
    TEST_BR_TAKEN 54, blt,  -1, 1
    TEST_BR_NOT   55, blt,  1, -1
    TEST_BR_NOT   56, blt,  3, 3
    TEST_BR_TAKEN 57, bge,  1, -1
    TEST_BR_TAKEN 58, bge,  3, 3
    TEST_BR_NOT   59, bge,  -1, 1
    TEST_BR_TAKEN 60, bltu, 1, -1
    TEST_BR_NOT   61, bltu, -1, 1
    TEST_BR_TAKEN 62, bgeu, -1, 1
    TEST_BR_TAKEN 63, bgeu, 3, 3
    TEST_BR_NOT   64, bgeu, 1, -1

    # backward branch: loop 5 times
    li   x31, 65
    li   x1, 0
    li   x2, 5
1:  addi x1, x1, 1
    bne  x1, x2, 1b
    li   x4, 5
    bne  x1, x4, fail

    # ---- lui / auipc ----
    li   x31, 70
    lui  x3, 0xFFFFF
    li   x4, 0xFFFFF000
    bne  x3, x4, fail

    li   x31, 71
1:  auipc x3, 0x1
    la   x4, 1b
    li   x5, 0x1000
    add  x4, x4, x5
    bne  x3, x4, fail

    # ---- jal / jalr ----
    li   x31, 80
    jal  x1, 2f
1:  j    fail
2:  la   x4, 1b
    bne  x1, x4, fail

    li   x31, 81
    la   x2, 2f
    jalr x1, 0(x2)
1:  j    fail
2:  la   x4, 1b
    bne  x1, x4, fail

    li   x31, 82                # target = (rs1 + imm) & ~1
    la   x2, 2f
    addi x2, x2, -3
    jalr x1, 4(x2)
1:  j    fail
2:  la   x4, 1b
    bne  x1, x4, fail

    li   x31, 83                # rd == rs1: jump uses the old rs1
    la   x2, 2f
    jalr x2, 0(x2)
1:  j    fail
2:  la   x4, 1b
    bne  x2, x4, fail

    li   x31, 84                # jal x0 writes nothing
    jal  x0, 1f
    j    fail
1:  bne  x0, zero, fail

    # ---- loads ----
    TEST_LD 90, lw,  0x80FF7F01, 0, tdata
    TEST_LD 91, lb,  0x00000001, 0, tdata
    TEST_LD 92, lb,  0x0000007F, 1, tdata
    TEST_LD 93, lb,  0xFFFFFFFF, 2, tdata
    TEST_LD 94, lb,  0xFFFFFF80, 3, tdata
    TEST_LD 95, lbu, 0x000000FF, 2, tdata
    TEST_LD 96, lbu, 0x00000080, 3, tdata
    TEST_LD 97, lh,  0x00007F01, 0, tdata
    TEST_LD 98, lh,  0xFFFF80FF, 2, tdata
    TEST_LD 99, lhu, 0x000080FF, 2, tdata
    TEST_LD 100, lw, 0xDEADBEEF, 4, tdata
    TEST_LD 101, lw, 0xDEADBEEF, -4, tdata_end  # negative offset

    # ---- stores ----
    TEST_ST 110, sw, lw,  0x12345678, 0x12345678, 0
    TEST_ST 111, sh, lhu, 0x0000BEEF, 0xBEEF, 4
    TEST_ST 112, sh, lhu, 0x0000CAFE, 0xCAFE, 6
    TEST_ST 113, sb, lbu, 0x000000AB, 0xAB, 1

    # byte lanes: the sb/sh above must not disturb their neighbours
    li   x31, 114
    la   x5, sbuf
    lw   x3, 0(x5)
    li   x4, 0x1234AB78
    bne  x3, x4, fail
    lw   x3, 4(x5)
    li   x4, 0xCAFEBEEF
    bne  x3, x4, fail

    li   x31, 115               # sb into every lane of a zeroed word
    sw   zero, 8(x5)
    li   x1, 0x11
    sb   x1, 8(x5)
    li   x1, 0x22
    sb   x1, 9(x5)
    li   x1, 0x33
    sb   x1, 10(x5)
    li   x1, 0x44
    sb   x1, 11(x5)
    lw   x3, 8(x5)
    li   x4, 0x44332211
    bne  x3, x4, fail

    # ---- done ----
pass:
    li   x1, TOHOST
    li   x2, 1
    sw   x2, 0(x1)
1:  j    1b

fail:
    slli x2, x31, 1
    ori  x2, x2, 1
    li   x1, TOHOST
    sw   x2, 0(x1)
1:  j    1b

.section .data
tdata:
    .word 0x80FF7F01
    .word 0xDEADBEEF
tdata_end:

sbuf:
    .word 0, 0, 0
