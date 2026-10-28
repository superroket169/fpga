// Simulation testbench for `top` in src/main.v (iverilog).
//
// Loads a $readmemh image into BRAM over the synth-time build/prog.hex,
// releases reset, and waits for the program to store to TOHOST:
//   1              = PASS
//   (n << 1) | 1   = FAIL in test n
// TOHOST sits in unmapped region 0xF, so the store has no effect on the
// hardware - the testbench just watches the bus for it.
//
// Plusargs:
//   +hex=<file>     image to load (required)
//   +max_cycles=<n> timeout, default 200000
//   +trace          print pc/instruction at every WRITEBACK
//   +vcd            dump waveforms to build/sim.vcd
//
// Run through scripts/sim.sh.
`timescale 1ns / 1ps

module testbench;
    localparam [31:0] TOHOST = 32'hF000_0000;
    localparam        WRITEBACK = 3'd4;

    reg clk   = 1'b0;
    reg rst_n = 1'b1; // top uses rst_n as active-high, see the NOTE in main.v

    wire [32:0] gpio;
    wire        uart0_tx, uart1_tx;

    top dut (
        .clk(clk),
        .rst_n(rst_n),
        .gpio(gpio),
        .uart0_tx(uart0_tx),
        .uart0_rx(1'b1),
        .uart1_tx(uart1_tx),
        .uart1_rx(1'b1)
    );

    always #18.5 clk = ~clk; // ~27MHz, only matters for reading waveforms

    reg [1023:0] hex_file;
    integer      max_cycles;
    integer      cycles = 0;
    integer      i;

    initial begin
        if (!$value$plusargs("hex=%s", hex_file)) begin
            $display("ERROR: +hex=<file> missing");
            $finish;
        end
        if (!$value$plusargs("max_cycles=%d", max_cycles))
            max_cycles = 200000;

        if ($test$plusargs("vcd")) begin
            $dumpfile("build/sim.vcd");
            $dumpvars(0, testbench);
        end

        // #1 so this runs after unified_memory's own $readmemh at t=0
        #1;
        for (i = 0; i < 22528; i = i + 1)
            dut.u_cpu.my_mem.u_bram.mem[i] = 32'b0;
        $readmemh(hex_file, dut.u_cpu.my_mem.u_bram.mem);

        repeat (5) @(posedge clk);
        rst_n = 1'b0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = cycles + 1;
            if (cycles >= max_cycles) begin
                $display("TIMEOUT after %0d cycles, pc=%08x", cycles, dut.u_cpu.pc);
                $finish;
            end
        end

        if ($test$plusargs("trace") && dut.u_cpu.state == WRITEBACK)
            $display("%08x: %08x", dut.u_cpu.pc, dut.u_cpu.IR);

        if (dut.u_cpu.mem_we && dut.u_cpu.mem_addr == TOHOST) begin
            if (dut.u_cpu.mem_store_data == 32'd1)
                $display("PASS (%0d cycles)", cycles);
            else
                $display("FAIL: test %0d (pc=%08x)",
                         dut.u_cpu.mem_store_data >> 1, dut.u_cpu.pc);
            $finish;
        end
    end
endmodule
