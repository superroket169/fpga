module top (
    input  wire        clk,
    input  wire        rst_n,
    inout  wire [34:0] gpio
);
    assign gpio[5:0] = {6{gpio[6]}};

endmodule
