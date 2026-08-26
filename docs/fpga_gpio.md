# Memory map

`addr[31:28]` selects a region. Only two are populated; the rest are
reserved for later (nothing hardware-specific planned for this MVP - any
UART/SPI needed is bit-banged through the GPIO region below).

// gpio[34:0] - generic memory-mapped GPIO bus, see fpga_gpio.md for the
// index-to-pin table. idx0-5 = onboard LEDs (active-low), idx6 = S2 button.
// idx7-34 = free header pins (idx10/pin85 and idx20/pin80 are shared with
// the TF card DAT1/DAT2 lines - avoid them if the SD slot is ever used).

| region (`addr[31:28]`) | base         | contents                         |
|-------------------------|--------------|-----------------------------------|
| `0x0`                    | `0x00000000` | unified BRAM, 88KB (code + data)  |
| `0x1`                    | `0x10000000` | GPIO (see below)                  |
| `0x2`-`0xF`              | -            | reserved, unmapped                |

Only `addr[16:2]` is decoded inside BRAM (22528 words = 88KB, 44 of the
GW2AR-18C's 46 BSRAM blocks - verified with an actual place&route run;
empirically each block only holds ~2KB usable in this byte-write-enabled
inference pattern, not the theoretical 2.25KB, so 2 blocks are left spare
on purpose), and only `addr[7:0]` is decoded inside GPIO - the middle
address bits are don't-cares. Use the canonical bases above (`0x10000000`
for GPIO) rather than an arbitrary `0x1_xxxxxxx` value.

## GPIO registers (base `0x10000000`)

37 pins, indexed 0-36, split across a low word (pins 0-31) and a high word
(pins 32-36).

| offset | name    | bits   | meaning                                         |
|--------|---------|--------|---------------------------------------------------|
| `0x00` | DIR_LO  | [31:0] | pin direction, 1=output 0=input. Reset: all input |
| `0x04` | DIR_HI  | [4:0]  | direction for pins 32-36                          |
| `0x08` | OUT_LO  | [31:0] | output latch (only drives the pin if DIR=1)       |
| `0x0C` | OUT_HI  | [4:0]  | output latch for pins 32-36                       |
| `0x10` | IN_LO   | [31:0] | live input level, read-only, registered 1 cycle   |
| `0x14` | IN_HI   | [4:0]  | live input level for pins 32-36                   |

Pins 0-5 (onboard LEDs) are wired active-low on this board; `gpio_ctrl` in
main.v corrects the polarity in hardware, so software always sees "1 =
lit / asserted" through OUT and IN regardless of pin. No other pin gets
this treatment.

A program must set DIR before OUT/IN do anything useful - e.g. to blink
the LEDs: write `0x3F` to DIR_LO, then toggle bits in OUT_LO.

## Pin table

Physical pin numbers are FPGA ball numbers (as used in `tangnano20k.cst`
`IO_LOC` lines), read directly off the two GPIO header rows on the board
(2026-08-25).

| idx | pin | notes                                      |
|-----|-----|---------------------------------------------|
| 0   | 15  | LED0 (active-low)                          |
| 1   | 16  | LED1 (active-low)                          |
| 2   | 17  | LED2 (active-low)                          |
| 3   | 18  | LED3 (active-low)                          |
| 4   | 19  | LED4 (active-low)                          |
| 5   | 20  | LED5 (active-low)                          |
| 6   | 87  | S2 button                                  |
| 7   | 73  | free - OLED CS                             |
| 8   | 74  | free - OLED DC                             |
| 9   | 75  | free - OLED RST                            |
| 10  | 85  | free, **shared w/ TF card DAT1** - avoid if SD used |
| 11  | 77  | free - OLED SCK (also LCD_CLK on RGB header) |
| 12  | 27  | free - OLED MOSI                           |
| 13  | 28  | free                                       |
| 14  | 25  | free                                       |
| 15  | 26  | free                                       |
| 16  | 29  | free                                       |
| 17  | 30  | free                                       |
| 18  | 31  | free                                       |
| 19  | 76  | free                                       |
| 20  | 80  | free, **shared w/ TF card DAT2** - avoid if SD used |
| 21  | 42  | free                                       |
| 22  | 41  | free                                       |
| 23  | 56  | free                                       |
| 24  | 54  | free                                       |
| 25  | 51  | free                                       |
| 26  | 48  | free                                       |
| 27  | 55  | free                                       |
| 28  | 49  | free                                       |
| 29  | 86  | free                                       |
| 30  | 79  | free                                       |
| 31  | 72  | free                                       |
| 32  | 71  | free                                       |
| 33  | 53  | free                                       |
| 34  | 52  | free                                       |
| 35  | 69  | onboard BL616 USB-UART bridge (TX, FPGA→PC) - reserved for the UART bootloader |
| 36  | 70  | onboard BL616 USB-UART bridge (RX, PC→FPGA) - reserved for the UART bootloader |

Pins 35/36 go through the same BL616 chip that also does JTAG/flashing, and
that chip talks to the PC over the board's single USB-C port - the exact
same cable already used to run `build.sh`. No separate USB-UART adapter or
second programmer is needed; the PC side will just show up as an extra
serial device (e.g. `/dev/ttyACM*`) alongside the programming interface.

## Pins NOT in the GPIO bus (dedicated, do not repurpose)

| signal      | pin   | reason                                                        |
|-------------|-------|----------------------------------------------------------------|
| clk         | 4     | main oscillator                                                |
| rst_n (S1)  | 88    | hardware CPU reset, wired straight into `cpu_core.rst`         |
| flash_*     | 59-62 | onboard SPI flash storing the bitstream                        |
| sd_clk/cmd  | 82-83 | TF card slot                                                   |
| sd_dat[0]/[3] | 84/81 | TF card slot                                                 |

## OLED wiring (SSD1306, bit-banged 4-wire SPI, no hardware SPI core)

| signal | gpio idx | pin |
|--------|----------|-----|
| CS     | 7        | 73  |
| DC     | 8        | 74  |
| RST    | 9        | 75  |
| SCK    | 11       | 77  |
| MOSI   | 12       | 27  |
