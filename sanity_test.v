module top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       button,
    output wire [5:0] led
);
    assign led[0] = button;
    assign led[1] = button;
    assign led[2] = button;
    assign led[3] = button;
    assign led[4] = button;
    assign led[5] = button;


endmodule
