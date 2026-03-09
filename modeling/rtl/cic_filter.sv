module cic_filter #(
    parameter int INPUT_WIDTH = 14,
    parameter int STAGES = 6,
    parameter int DECIMATION = 125
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [INPUT_WIDTH-1:0] d_in,
    output logic                     d_out_valid,
    output wire signed [63:0]       d_out  // Wide output to accommodate bit growth
);

    // -------------------------------------------------------------------------
    // Bit Growth Calculation
    // Max Gain = R^N.
    // Bits = N * ceil(log2(R)).
    // For R=125, ceil(log2(125)) = 7.
    // Growth = 6 * 7 = 42 bits.
    // Total Width = 14 + 42 = 56 bits.
    // We use 64 bits for convenience.
    // -------------------------------------------------------------------------
    localparam int INTERNAL_WIDTH = 64;

    // -------------------------------------------------------------------------
    // Integrator Section (Clock Rate)
    // -------------------------------------------------------------------------
    logic signed [INTERNAL_WIDTH-1:0] int_stages [0:STAGES-1];
    logic signed [INTERNAL_WIDTH-1:0] int_next [0:STAGES-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < STAGES; i++) begin
                int_stages[i] <= '0;
            end
        end else begin
            // Stage 0 input is extended d_in
            int_stages[0] <= int_stages[0] + signed'(d_in);
            
            // Subsequent stages accumulate previous stage
            for (int i = 1; i < STAGES; i++) begin
                int_stages[i] <= int_stages[i] + int_stages[i-1];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Decimation
    // -------------------------------------------------------------------------
    logic [$clog2(DECIMATION)-1:0] dec_cnt;
    logic dec_enable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_cnt <= '0;
            dec_enable <= 1'b0;
        end else begin
            if (dec_cnt == DECIMATION - 1) begin
                dec_cnt <= '0;
                dec_enable <= 1'b1;
            end else begin
                dec_cnt <= dec_cnt + 1;
                dec_enable <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Comb Section (Decimated Rate)
    // -------------------------------------------------------------------------
    logic signed [INTERNAL_WIDTH-1:0] comb_stages [0:STAGES-1];
    logic signed [INTERNAL_WIDTH-1:0] comb_delayed [0:STAGES-1];
    
    // Wire to connect Integrator Last Stage to Comb First Stage
    logic signed [INTERNAL_WIDTH-1:0] comb_input;
    assign comb_input = int_stages[STAGES-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < STAGES; i++) begin
                comb_stages[i] <= '0;
                comb_delayed[i] <= '0;
            end
            d_out_valid <= 1'b0;
        end else if (dec_enable) begin
            // Stage 0
            comb_delayed[0] <= comb_input;
            comb_stages[0]  <= comb_input - comb_delayed[0];
            
            // Subsequent stages
            for (int i = 1; i < STAGES; i++) begin
                comb_delayed[i] <= comb_stages[i-1];
                comb_stages[i]  <= comb_stages[i-1] - comb_delayed[i];
            end
            
            d_out_valid <= 1'b1;
        end else begin
            d_out_valid <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------------
    assign d_out = comb_stages[STAGES-1];

endmodule
