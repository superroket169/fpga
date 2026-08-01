module cpu_tb;
    reg clk, rst;
    cpu_core uut (.clk(clk), .rst(rst));
    always #50 clk = ~clk;
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);
        clk = 0; rst = 1;
        $monitor("t=%0t state=%0d pc=%0d x10=%0d", $time, uut.state, uut.pc, uut.my_regs.regs[10]);
        #120 rst = 0;
        repeat(500) @(posedge clk);
        #10 $finish;
    end
endmodule
