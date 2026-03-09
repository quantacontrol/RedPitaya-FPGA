module prng (
    input  wire               clk,
    input  wire               rst_n,
    output wire signed [13:0] noise_out
);
    reg [31:0] lfsr_state;

    // Xorshift32 combinational logic (moved outside always_ff)
    logic [31:0] t1, t2, t3;

    always_comb begin
        // Xorshift32 algorithm
        // x ^= x << 13;
        // x ^= x >> 17;
        // x ^= x << 5;
        t1 = lfsr_state ^ (lfsr_state << 13);
        t2 = t1 ^ (t1 >> 17);
        t3 = t2 ^ (t2 << 5);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state <= 32'hACE12345; // Non-zero seed
        end else begin
            lfsr_state <= t3;
        end
    end

    // Map 32-bit uniform to 14-bit signed centered roughly around 0
    // Simple way: take top 14 bits.
    // To center it: subtract half range, or just treat as 2's complement.
    // If we treat [31:18] as signed 14-bit:
    // It covers full range. Mean is roughly 0.
    assign noise_out = signed'(lfsr_state[31:18]);

endmodule
