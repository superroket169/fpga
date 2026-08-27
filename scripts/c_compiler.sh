#!/usr/bin/env bash
# Compiles a freestanding RV32I C file into build/<name>.{o,elf,hex,bin}.
# No libc (-ffreestanding -nostdlib) - nothing here can call printf/malloc/
# exit, so it's safe even though this CPU doesn't handle ecall/ebreak yet.
#
# Usage: scripts/c_compiler.sh <c_file> [output_name] [text_addr]
#   c_file      - the .c source to compile
#   output_name - default: the .c file's basename (output under build/)
#   text_addr   - default: 0x0  (link address; use 0x400 for a program
#                 meant to be loaded via the UART bootloader)
#
# .hex is the $readmemh-compatible format main.v's BRAM loads at synth time.
# .bin is the raw machine code scripts/uart_load.py sends over the wire.

set -euo pipefail
cd "$(dirname "$0")/.."

C_FILE="${1:?usage: c_compiler.sh <c_file> [output_name] [text_addr]}"
OUT_NAME="${2:-$(basename "$C_FILE" .c)}"
TEXT_ADDR="${3:-0x0}"

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

O_FILE="${BUILD_DIR}/${OUT_NAME}.o"
ELF_FILE="${BUILD_DIR}/${OUT_NAME}.elf"
HEX_FILE="${BUILD_DIR}/${OUT_NAME}.hex"
BIN_FILE="${BUILD_DIR}/${OUT_NAME}.bin"

riscv64-elf-gcc -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -O1 \
    -c "$C_FILE" -o "$O_FILE"
riscv32-elf-ld -T src/link.ld --defsym=ORIGIN_ADDR="$TEXT_ADDR" -o "$ELF_FILE" "$O_FILE"
riscv32-elf-objcopy -O verilog --verilog-data-width=4 "$ELF_FILE" "$HEX_FILE"
riscv32-elf-objcopy -O binary "$ELF_FILE" "$BIN_FILE"

echo "OK: ${ELF_FILE}"
echo "    ${HEX_FILE}  (main.v \$readmemh icin)"
echo "    ${BIN_FILE}  (scripts/uart_load.py icin)"
