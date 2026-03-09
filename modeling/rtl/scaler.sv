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
    
    logic signed [83:0] mult_res; // 64 + 20

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_valid <= 0;
            dout <= 0;
            mult_res <= 0;
        end else begin
            dout_valid <= din_valid;
            if (din_valid) begin
                automatic logic signed [83:0] m = din * COEFF;
                automatic logic signed [31:0] s = m >>> SHIFT;
                mult_res <= m;
                
                // Saturation logic
                if (s > 32'sd8191) 
                    dout <= 14'sd8191;
                else if (s < -32'sd8192) 
                    dout <= -14'sd8192;
                else 
                    dout <= s[13:0];
            end
        end
    end
endmodule
