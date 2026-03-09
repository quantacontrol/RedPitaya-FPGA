module sine_gen (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [31:0]            phase_inc,
    output wire signed [13:0]     sine_out
);

    reg [31:0] phase_acc;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 32'd0;
        end else begin
            phase_acc <= phase_acc + phase_inc;
        end
    end

    // Use top 10 bits for 1024-entry LUT
    wire [9:0] lut_addr = phase_acc[31:22];

    sine_lut sine_lut_i (
        .clk  (clk),
        .addr (lut_addr),
        .data (sine_out)
    );

endmodule
