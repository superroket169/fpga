#!/usr/bin/env bash
# Sends a compiled program to the board over UART - finds the right USB port itself
#
# Usage: scripts/load.sh <bin_file>
# Example: scripts/load.sh build/led_button_test.bin

set -euo pipefail
cd "$(dirname "$0")/.."

BIN_FILE="${1:?usage: load.sh <bin_file>}"

PORT=$(ls /dev/serial/by-id/*if01* 2>/dev/null | head -1 || true)
if [[ -z "$PORT" ]]; then
    echo "ERROR: device not found" >&2
    exit 1
fi

echo "Device found: $PORT"
python3 scripts/uart_load.py "$PORT" "$BIN_FILE"
