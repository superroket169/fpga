#!/usr/bin/env bash
# Assembles an RV32I .s file into build/<name>.{o,elf,hex,bin}.
#
# Usage: scripts/program_translater.sh <asm_file> [output_name] [text_addr]
#   asm_file    - the .s source to assemble (examples/ holds these now)
#   output_name - default: the .s file's basename (output under build/)
#   text_addr   - default: 0x0          (link address; use 0x400 for a
#                 program meant to be loaded via the UART bootloader)
#
# .hex is the $readmemh-compatible format main.v's BRAM loads at synth time.
# .bin is the raw machine code scripts/uart_load.py sends over the wire.
set -euo pipefail
cd "$(dirname "$0")/.."

ASM_FILE="${1:?usage: program_translater.sh <asm_file> [output_name] [text_addr]}"
OUT_NAME="${2:-$(basename "$ASM_FILE" .s)}"
TEXT_ADDR="${3:-0x0}"

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

O_FILE="${BUILD_DIR}/${OUT_NAME}.o"
ELF_FILE="${BUILD_DIR}/${OUT_NAME}.elf"
HEX_FILE="${BUILD_DIR}/${OUT_NAME}.hex"
BIN_FILE="${BUILD_DIR}/${OUT_NAME}.bin"

riscv32-elf-as -march=rv32i -mabi=ilp32 -o "$O_FILE" "$ASM_FILE"
riscv32-elf-ld -T src/link.ld --defsym=ORIGIN_ADDR="$TEXT_ADDR" -o "$ELF_FILE" "$O_FILE"
riscv32-elf-objcopy -O verilog --verilog-data-width=4 "$ELF_FILE" "$HEX_FILE"
riscv32-elf-objcopy -O binary "$ELF_FILE" "$BIN_FILE"

echo "OK: ${ELF_FILE}"
echo "    ${HEX_FILE}  (main.v \$readmemh icin)"
echo "    ${BIN_FILE}  (scripts/uart_load.py icin)"
