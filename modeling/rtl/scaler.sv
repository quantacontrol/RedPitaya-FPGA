module scaler (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   din_valid,
    input  wire signed [63:0]     din,
    output logic                  dout_valid,
    output logic signed [13:0]    dout
);
    // Factor to correct for 125^6 gain and bring to 14-bit
    // Target Divisor: 125^6 = 3.814e12
    // We implement (din * MULT) >>> SHIFT
    // Let SHIFT = 60
    // MULT = 2^60 / 125^6 = 302231
    
    localparam signed [19:0] COEFF = 20'd302231;
    localparam int SHIFT = 60;
    
    // Pipeline Stage 1: Multiplication
    logic signed [83:0] mult_res; // 64 + 20
    logic               stage1_valid;

    // Temporary for pipelined logic (module-level for iverilog compat)
    logic signed [31:0] s;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_res <= 0;
            stage1_valid <= 0;
            dout <= 0;
            dout_valid <= 0;
        end else begin
            // Stage 1: Multiplier
            if (din_valid) begin
                mult_res <= din * COEFF;
                stage1_valid <= 1'b1;
            end else begin
                stage1_valid <= 1'b0;
            end

            // Stage 2: Shift and Saturate
            if (stage1_valid) begin
                s = 32'(mult_res >>> SHIFT);
                
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
