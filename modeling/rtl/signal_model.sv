// =============================================================================
// signal_model.sv -- Disturbance Signal Generator
//
// Purpose: Generates a multi-tone disturbance signal (3 sine waves at different
//          frequencies) to simulate environmental disturbances for closed-loop
//          control testing. The output is intended to be sent through DAC OUT1,
//          physically looped back to ADC IN1, where real-world noise is naturally
//          introduced by the DAC/ADC analog path.
//
// Inputs:
//   clk        - System clock (125 MHz)
//   rst_n      - Active-low reset
//   gain1_in   - Q16.16 gain for 0.5 Hz sine (slow drift)
//   gain2_in   - Q16.16 gain for 330 Hz sine (mechanical vibration)
//   gain3_in   - Q16.16 gain for 1200 Hz sine (acoustic noise)
//
// Outputs:
//   disturbance_out - 14-bit signed disturbance signal (sum of 3 weighted sines)
// =============================================================================
module signal_model (
    input  wire                   clk,
    input  wire                   rst_n,
    // Configuration Inputs
    input  wire signed [31:0]     gain1_in,
    input  wire signed [31:0]     gain2_in,
    input  wire signed [31:0]     gain3_in,
    
    output wire signed [13:0]     disturbance_out
);

    // =========================================================================
    // Parameters (Calculated for 125MHz FS)
    // =========================================================================
    localparam [31:0] INC_0_5HZ  = 32'd17;
    localparam [31:0] INC_330HZ  = 32'd11337;
    localparam [31:0] INC_1200HZ = 32'd41227;

    // =========================================================================
    // Sine Generators
    // =========================================================================
    wire signed [13:0] s1, s2, s3;
    
    sine_gen gen1 (
        .clk(clk), .rst_n(rst_n), .phase_inc(INC_0_5HZ), .sine_out(s1)
    );
    
    sine_gen gen2 (
        .clk(clk), .rst_n(rst_n), .phase_inc(INC_330HZ), .sine_out(s2)
    );
    
    sine_gen gen3 (
        .clk(clk), .rst_n(rst_n), .phase_inc(INC_1200HZ), .sine_out(s3)
    );

    // =========================================================================
    // Summation with Pipeline
    // =========================================================================
    // Use 64-bit to prevent overflow during intermediate calculations (Q30.16)
    reg signed [63:0] term1, term2, term3;
    reg signed [63:0] disturbance_sum_q;
    
    // Combinational sum of all disturbance terms (no noise, no feedback)
    wire signed [63:0] disturbance_sum_wire;
    assign disturbance_sum_wire = term1 + term2 + term3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            term1      <= 0;
            term2      <= 0;
            term3      <= 0;
            disturbance_sum_q <= 0;
        end else begin
            // Stage 1: Multiplication (Gains are Q16.16)
            // Sine (Q14.0) * Gain (Q16.16) = Q30.16
            term1      <= 64'(s1) * gain1_in;
            term2      <= 64'(s2) * gain2_in;
            term3      <= 64'(s3) * gain3_in;
            
            // Stage 2: Summation (All Q30.16)
            disturbance_sum_q <= disturbance_sum_wire;
        end
    end
    
    function signed [13:0] saturate14(input signed [63:0] val);
        if (val > 64'sd8191) 
            return 14'sd8191;
        else if (val < -64'sd8192) 
            return -14'sd8192;
        else 
            return val[13:0];
    endfunction

    reg signed [13:0] disturbance_out_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disturbance_out_q <= 14'sd0;
        end else begin
            disturbance_out_q <= saturate14(disturbance_sum_q >>> 16);
        end
    end

    assign disturbance_out = disturbance_out_q;

endmodule
