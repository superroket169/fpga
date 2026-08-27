/* UART bootloader. Lives at BRAM address 0, runs on every reset.
 *
 * Frame: [4-byte LE length][payload][1-byte checksum = sum(payload) mod 256]
 * Loads payload at 0x400 then jumps there. No return channel to the PC -
 * LEDs (idx0-5) show status: LED0=waiting, LED0+1=receiving,
 * flash once=jumping to program, blink forever=bad frame.
 *
 * See docs/fpga_gpio.md for pins, scripts/c_compiler.sh for the build.
 */

#define GPIO_BASE   0x10000000u
#define GPIO_DIR_LO (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR_HI (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_OUT_LO (*(volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_IN_HI  (*(volatile unsigned int *)(GPIO_BASE + 0x14))

#define RX_BIT       (1u << 4)   /* idx36 (RX) = bit4 of the high word */
#define PROGRAM_ADDR 0x400u      /* where a loaded program starts */
#define STACK_TOP    0x16000u    /* top of the 88KB BRAM (used by _reset) */
#define MAX_PAYLOAD  88576u      /* 0x15800: 1KB headroom below STACK_TOP,
                                     so a max-size payload can't grow into
                                     the bootloader's own stack while receiving */

/* 9600 baud @ 27MHz = ~2812 cycles/bit. BIT_DELAY_ITERS/HALF_BIT_ITERS
 * are calibrated for -O1 exactly (see scripts/c_compiler.sh) - a different
 * optimization level changes delay()'s instruction count and breaks timing. */
#define BIT_DELAY_ITERS 109u
#define HALF_BIT_ITERS  54u
#define FLASH_ITERS     500000u
#define BLINK_ITERS     1000000u

typedef void (*entry_fn)(void);

static void delay(unsigned int iters);
static unsigned char recv_byte(void);

/* sp resets to 0 with no crt0 to fix it - the first function call would
 * underflow it and corrupt BRAM. This sets it first; link.ld's .text.entry
 * guarantees it's what the CPU fetches at address 0. */
__attribute__((naked, section(".text.entry")))
void _reset(void) {
    __asm__ volatile (
        "li sp, %0\n"
        "j main\n"
        :: "i"(STACK_TOP)
    );
}

void main(void) {
    GPIO_DIR_LO = 0x3F; /* LEDs (idx0-5) = output */
    GPIO_DIR_HI = 0x00; /* everything else, incl. RX/TX, stays input */

    GPIO_OUT_LO = 0x01; /* waiting for the length header */

    unsigned int length = (unsigned int)recv_byte();
    length |= (unsigned int)recv_byte() << 8;
    length |= (unsigned int)recv_byte() << 16;
    length |= (unsigned int)recv_byte() << 24;

    int ok = (length < MAX_PAYLOAD);

    if (ok) {
        GPIO_OUT_LO = 0x03; /* receiving payload */

        unsigned char *dest = (unsigned char *)PROGRAM_ADDR;
        unsigned int checksum = 0;
        for (unsigned int i = 0; i < length; i++) {
            unsigned char b = recv_byte();
            dest[i] = b;
            checksum += b;
        }

        unsigned char recv_checksum = recv_byte();
        ok = (recv_checksum == (unsigned char)checksum);
    }

    if (ok) {
        GPIO_OUT_LO = 0x3F; /* flash all 6 LEDs: load OK */
        delay(FLASH_ITERS);
        ((entry_fn)PROGRAM_ADDR)(); /* jump into the loaded program */
    }

    for (;;) { /* bad frame: blink forever */
        GPIO_OUT_LO = 0x3F;
        delay(BLINK_ITERS);
        GPIO_OUT_LO = 0x00;
        delay(BLINK_ITERS);
    }
}

static void delay(unsigned int iters) {
    volatile unsigned int i = iters;
    while (i != 0) {
        i--;
    }
}

static unsigned char recv_byte(void) {
    unsigned int byte = 0;

    /* make sure we start from an idle-high line, then wait for the
     * falling edge (start bit) */
    while ((GPIO_IN_HI & RX_BIT) == 0) { }
    while ((GPIO_IN_HI & RX_BIT) != 0) { }

    delay(HALF_BIT_ITERS); /* land in the middle of the start bit */

    for (int i = 0; i < 8; i++) {
        delay(BIT_DELAY_ITERS); /* advance to the middle of the next bit */
        if (GPIO_IN_HI & RX_BIT) {
            byte |= (1u << i); /* LSB first */
        }
    }

    delay(BIT_DELAY_ITERS); /* ride out the stop bit */
    return (unsigned char)byte;
}
