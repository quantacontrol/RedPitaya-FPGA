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
    
    // Limits for 14-bit signed output, scaled to internal precision
    localparam signed [47:0] INT_MAX = 48'sd8191 << SHIFT;
    localparam signed [47:0] INT_MIN = -48'sd8192 << SHIFT;

    // Pipeline Stage 1: Multiplication
    logic signed [47:0] p_prod;
    logic signed [47:0] i_prod;
    logic               stage1_valid;

    // Pipeline Stage 2: Accumulation and Summation
    logic signed [47:0] integrator_full;
    logic signed [47:0] next_int_full;
    logic signed [47:0] sum_full;
    logic               stage2_valid;

    // Temporaries for pipelined logic (module-level for iverilog compat)
    logic signed [47:0] tmp_int;
    logic signed [31:0] s;

    // Sequential Logic for Pipelining
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_prod <= 48'sd0;
            i_prod <= 48'sd0;
            stage1_valid <= 1'b0;
            
            integrator_full <= 48'sd0;
            sum_full <= 48'sd0;
            stage2_valid <= 1'b0;
            
            dout <= 14'sd0;
            dout_valid <= 1'b0;
        end else begin
            // Stage 1: Multiply
            // P term: 14x32 -> 46 bits
            // I term: 14x32 -> 46 bits
            p_prod <= 64'(din) * kp_in;
            i_prod <= 64'(din) * ki_in;
            stage1_valid <= din_valid;

            // Stage 2: Accumulate and Sum
            if (stage1_valid) begin
                // Update Integrator
                tmp_int = integrator_full + i_prod;
                
                // Clamp Integrator
                if (tmp_int > INT_MAX) tmp_int = INT_MAX;
                else if (tmp_int < INT_MIN) tmp_int = INT_MIN;
                
                integrator_full <= tmp_int;
                
                // Sum P and I terms (P is scaled, I is unscaled in integrator)
                // P is Q16.16, integrator is Q14.16. Sum is Q16.16?
                // Actually p_prod is 14x32 -> 46-bit. Integrator is 48-bit.
                sum_full <= p_prod + tmp_int;
                stage2_valid <= 1'b1;
            end else begin
                stage2_valid <= 1'b0;
            end

            // Stage 3: Clamp and Output
            if (stage2_valid) begin
                s = 32'(sum_full >>> SHIFT);
                
                if (s > 32'sd8191) 
                    dout <= 14'sd8191;
                else if (s < -32'sd8192) 
                    dout <= -14'sd8192;
                else 
                    dout <= s[13:0];
                
                dout_valid <= 1'b1;
            end else begin
                dout_valid <= 1'b0;
            end
        end
    end

endmodule
