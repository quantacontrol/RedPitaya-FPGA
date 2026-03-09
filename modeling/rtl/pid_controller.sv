module pid_controller (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   din_valid,
    input  wire signed [13:0]     din,      // Error
    input  wire signed [31:0]     kp_in,    // Scaled Kp (Q16.16)
    input  wire signed [31:0]     ki_in,    // Scaled Ki (Q16.16)
    output logic                  dout_valid,
    output logic signed [13:0]    dout      // Feedback
);

    localparam int SHIFT = 16;
    
    // Integrator with higher precision (Q14.16 internal)
    logic signed [47:0] integrator_full;
    logic signed [31:0] p_term;
    logic signed [31:0] i_term_val;
    logic signed [31:0] feedback_full;
    logic signed [47:0] next_int_full;
    
    // Limits for 14-bit signed output, scaled to internal precision
    localparam signed [47:0] INT_MAX = 48'sd8191 <<< SHIFT;
    localparam signed [47:0] INT_MIN = -48'sd8192 <<< SHIFT;

    always_comb begin
        // 1. Calculate P and I terms
        // P term: Q14.0 * Q16.16 -> Q30.16 -> Q30.0 (shifted)
        p_term = 32'( (64'(din) * kp_in) >>> SHIFT );
        
        // I term: Q14.0 * Q16.16 -> Q30.16
        // We accumulate this full product
        next_int_full = integrator_full + (64'(din) * ki_in);
        
        // 2. Clamp Integrator (at Q30.16 level)
        if (next_int_full > INT_MAX) next_int_full = INT_MAX;
        else if (next_int_full < INT_MIN) next_int_full = INT_MIN;
        
        // 3. Convert Integrator to Q14.0 for summation
        i_term_val = 32'(next_int_full >>> SHIFT);
        
        // 4. Calculate Full Feedback
        feedback_full = p_term + i_term_val;
        
        // 5. Clamp Output
        if (feedback_full > 32'sd8191) feedback_full = 32'sd8191;
        else if (feedback_full < -32'sd8192) feedback_full = -32'sd8192;
    end

    // Sequential Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integrator_full <= 0;
            dout_valid <= 0;
            dout <= 0;
        end else if (din_valid) begin
            integrator_full <= next_int_full;
            dout <= feedback_full[13:0];
            dout_valid <= 1;
        end else begin
            dout_valid <= 0;
        end
    end

endmodule
