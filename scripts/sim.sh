#!/usr/bin/env bash
# Assembles a test program and runs it on src/main.v in iverilog,
# see sim/testbench.v for the PASS/FAIL protocol.
#
# Usage: scripts/sim.sh [asm_file] [plusargs...]
#   asm_file - default: sim/rv32i.s
#   plusargs - passed to the testbench, e.g. +trace +vcd +max_cycles=1000000
#
# Exit status: 0 on PASS, 1 on FAIL/TIMEOUT.

set -euo pipefail
cd "$(dirname "$0")/.."

ASM_FILE="${1:-sim/rv32i.s}"
shift || true
NAME="$(basename "$ASM_FILE" .s)"

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

scripts/program_translater.sh "$ASM_FILE" "$NAME" >/dev/null
iverilog -g2012 -o "${BUILD_DIR}/sim.vvp" -s testbench sim/testbench.v src/main.v

vvp -n "${BUILD_DIR}/sim.vvp" +hex="${BUILD_DIR}/${NAME}.hex" "$@" | tee "${BUILD_DIR}/sim.log"
grep -q '^PASS' "${BUILD_DIR}/sim.log"
