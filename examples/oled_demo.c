/* OLED (SSD1306 128x64, 4-wire bit-banged SPI, CS grounded on the module)
 * demo. Loaded through the UART bootloader at 0x400 - see
 * docs/fpga_gpio.md for wiring (SCK=idx11/pin77, MOSI=idx12/pin27,
 * RES=idx9/pin75, DC=idx8/pin74).
 *
 * Build: scripts/c_compiler.sh src/oled_demo.c oled_demo 0x400
 * Load:  scripts/load.sh build/oled_demo.bin
 */

#define GPIO_BASE   0x10000000u
#define GPIO_DIR_LO (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_OUT_LO (*(volatile unsigned int *)(GPIO_BASE + 0x08))

#define LED_BITS  0x3Fu          /* idx0-5 */
#define DC_BIT    (1u << 8)      /* idx8 */
#define RES_BIT   (1u << 9)      /* idx9 */
#define SCK_BIT   (1u << 11)     /* idx11 */
#define MOSI_BIT  (1u << 12)     /* idx12 */

static unsigned int out_shadow = 0;

static void gpio_set(unsigned int bit, int level) {
    if (level) out_shadow |= bit; else out_shadow &= ~bit;
    GPIO_OUT_LO = out_shadow;
}

static void delay(unsigned int iters) {
    volatile unsigned int i = iters;
    while (i != 0) i--;
}

static void spi_write(unsigned char byte) {
    for (int i = 7; i >= 0; i--) {
        gpio_set(MOSI_BIT, byte & (1u << i));
        gpio_set(SCK_BIT, 1); /* SSD1306 samples MOSI on the rising edge */
        gpio_set(SCK_BIT, 0);
    }
}

static void oled_cmd(unsigned char byte) {
    gpio_set(DC_BIT, 0);
    spi_write(byte);
}

static void oled_data(unsigned char byte) {
    gpio_set(DC_BIT, 1);
    spi_write(byte);
}

static void oled_init(void) {
    gpio_set(RES_BIT, 0);
    delay(10000);
    gpio_set(RES_BIT, 1);
    delay(10000);

    static const unsigned char init_cmds[] = {
        0xAE,       /* display off */
        0xD5, 0x80, /* clock divide ratio / oscillator freq */
        0xA8, 0x3F, /* multiplex ratio = 64 */
        0xD3, 0x00, /* display offset = 0 */
        0x40,       /* start line = 0 */
        0x8D, 0x14, /* charge pump on */
        0xA1,       /* segment remap */
        0xC8,       /* COM output scan direction, remapped */
        0xDA, 0x12, /* COM pins hardware config */
        0x81, 0xCF, /* contrast */
        0xD9, 0xF1, /* pre-charge period */
        0xDB, 0x40, /* VCOMH deselect level */
        0xA4,       /* display shows RAM contents */
        0xA6,       /* normal (not inverted) */
        0xAF,       /* display on */
    };
    for (unsigned int i = 0; i < sizeof(init_cmds); i++) {
        oled_cmd(init_cmds[i]);
    }
}

/* 8 pages x 128 columns, 1 bit per pixel (bit0 = top row of the page).
 * Global .bss is NOT zero-filled at startup (see src/link.ld) - this is
 * cleared by hand in main() before use, not left to rely on that. */
static unsigned char framebuf[8 * 128];

static void set_pixel(int x, int y) {
    if (x < 0 || x > 127 || y < 0 || y > 63) return;
    framebuf[(y / 8) * 128 + x] |= (unsigned char)(1u << (y % 8));
}

static void build_frame(void) {
    for (int x = 0; x < 128; x++) {
        set_pixel(x, 0);
        set_pixel(x, 63);
        set_pixel(x, x / 2); /* diagonal: 128 wide -> 64 tall, slope 1/2 */
    }
    for (int y = 0; y < 64; y++) {
        set_pixel(0, y);
        set_pixel(127, y);
    }
}

static void oled_flush(void) {
    for (unsigned int page = 0; page < 8; page++) {
        oled_cmd((unsigned char)(0xB0 | page)); /* page address */
        oled_cmd(0x00); /* column address low nibble = 0 */
        oled_cmd(0x10); /* column address high nibble = 0 */
        for (unsigned int col = 0; col < 128; col++) {
            oled_data(framebuf[page * 128 + col]);
        }
    }
}

__attribute__((section(".text.entry")))
void main(void) {
    GPIO_DIR_LO = LED_BITS | DC_BIT | RES_BIT | SCK_BIT | MOSI_BIT;

    for (unsigned int i = 0; i < sizeof(framebuf); i++) {
        framebuf[i] = 0;
    }

    oled_init();
    build_frame();
    oled_flush();

    out_shadow |= 0x01; /* LED0 = done */
    GPIO_OUT_LO = out_shadow;

    for (;;) { }
}
