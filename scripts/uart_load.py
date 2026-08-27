#!/usr/bin/env python3
"""
PC-side sender for the Tang Nano 20K UART bootloader (see prog.s).

Sends a raw binary over the board's USB-UART bridge (BL616 - the same
Type-C cable used to flash it) in the frame the bootloader expects:

    [4 bytes length, little-endian] [length bytes payload] [1 byte checksum]
    checksum = (sum of all payload bytes) mod 256

One-way: this never reads anything back, because the bootloader never
drives TX. Watch the onboard LEDs instead - see the status table at the top of prog.s.

Usage:
    python3 uart_load.py <port> <binary_file> [baud]

Example:
    python3 uart_load.py /dev/ttyACM0 firmware.bin
"""
import sys
import time

import serial  # pip install pyserial

DEFAULT_BAUD = 9600


def main():
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <port> <binary_file> [baud]", file=sys.stderr)
        sys.exit(1)

    port = sys.argv[1]
    path = sys.argv[2]
    baud = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_BAUD

    with open(path, "rb") as f:
        payload = f.read()

    length = len(payload)
    checksum = sum(payload) & 0xFF
    frame = length.to_bytes(4, "little") + payload + bytes([checksum])

    print(f"{path}: {length} bytes, checksum 0x{checksum:02x}, opening {port} @ {baud}")

    with serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=1) as ser:
        # let the board settle after the port opens (DTR toggles can pulse
        # reset on some USB-serial bridges) before the bootloader's first
        # sample window
        
        time.sleep(0.2)
        ser.write(frame)
        ser.flush()

    print("sent. watch the LEDs: solid = still loading, one flash = OK, blinking = bad frame.")


if __name__ == "__main__":
    main()
