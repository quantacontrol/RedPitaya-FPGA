// =============================================================================
// feedback_controller_top.sv -- Closed-Loop Feedback Controller with Real DAC/ADC Path
//
// Purpose: Implements a closed-loop feedback controller that uses the physical
//          DAC OUT1 -> ADC IN1 path for realistic noise injection.
//
// Architecture:
//   1. Signal Model generates a multi-tone disturbance signal (no simulated noise).
//   2. Disturbance + PID feedback are summed and output to DAC OUT1 (dac_out_o).
//   3. The signal travels through the physical analog path (DAC -> cable -> ADC),
//      naturally acquiring real-world white noise.
//   4. ADC IN1 (adc_dat_a_i) captures the signal with real noise.
//   5. The ADC input is filtered through CIC decimation and fed to the PID.
//   6. The PID output (feedback) is added to the disturbance at the DAC output,
//      closing the loop to drive the ADC reading toward the setpoint.
//
// Signal Flow:
//   signal_model ─┐
//                  ├─(sum)─► dac_out_o ─► DAC OUT1 ─► (cable) ─► ADC IN1
//   PID feedback ──┘                                              │
//        ▲                                                        ▼
//        └────── PID ◄── scaler ◄── CIC ◄──────────────── adc_dat_a_i
//
// Register Map (base address: 0x40900000):
//   0x00: control     [0]=Enable, [1]=PID reset, [2]=Mode(0=open,1=closed),
//                      [3]=CIC enable
//   0x04: kp          Proportional gain (Q16.16)
//   0x08: ki          Integral gain (Q16.16)
//   0x0C: setpoint    14-bit setpoint (reserved for future use)
//   0x10: sig_gen_1   Sine generator 1 gain (Q16.16, 0.5 Hz)
//   0x14: sig_gen_2   Sine generator 2 gain (Q16.16, 330 Hz)
//   0x18: sig_gen_3   Sine generator 3 gain (Q16.16, 1200 Hz)
//   0x1C: (reserved)  Was noise_cfg, no longer used
//   0x20: out_mux_ch1 Scope CH1 signal select
//   0x24: out_mux_ch2 Scope CH2 signal select
// =============================================================================
module feedback_controller_top (
    input  wire             clk_i,
    input  wire             rst_n_i,
    
    // System Bus (AXI4-Lite adapted)
    input  wire [31:0]      sys_addr_i,
    input  wire [31:0]      sys_wdata_i,
    input  wire             sys_wen_i,
    input  wire             sys_ren_i,
    output reg  [31:0]      sys_rdata_o,
    output reg              sys_err_o,
    output reg              sys_ack_o,
    
    // External ADC/DAC/Scope Connections
    input  wire signed [13:0] adc_dat_a_i,
    input  wire signed [13:0] adc_dat_b_i,
    output wire signed [13:0] dac_out_o,     // DAC output for OUT1
    output wire signed [13:0] scope_ch1_o,
    output wire signed [13:0] scope_ch2_o
);

    // =========================================================================
    // Registers
    // =========================================================================
    reg [31:0] reg_control;    // 0x00
    reg [31:0] reg_kp;         // 0x04 (Q16.16)
    reg [31:0] reg_ki;         // 0x08 (Q16.16)
    reg [13:0] reg_setpoint;   // 0x0C
    reg [31:0] reg_sig_gen_1;  // 0x10 (Q16.16)
    reg [31:0] reg_sig_gen_2;  // 0x14 (Q16.16)
    reg [31:0] reg_sig_gen_3;  // 0x18 (Q16.16)
    reg [ 2:0] reg_output_mux_ch1; // 0x20
    reg [ 2:0] reg_output_mux_ch2; // 0x24

    // =========================================================================
    // Input Registers for Timing
    // =========================================================================
    reg [31:0]      sys_addr_q;
    reg [31:0]      sys_wdata_q;
    reg             sys_wen_q;
    reg             sys_ren_q;
    reg signed [13:0] adc_dat_a_q;
    reg signed [13:0] adc_dat_b_q;

    always_ff @(posedge clk_i) begin
        sys_addr_q  <= sys_addr_i;
        sys_wdata_q <= sys_wdata_i;
        sys_wen_q   <= sys_wen_i;
        sys_ren_q   <= sys_ren_i;
        adc_dat_a_q <= adc_dat_a_i;
        adc_dat_b_q <= adc_dat_b_i;
    end

    // =========================================================================
    // Bus Logic (matching Red Pitaya bus protocol)
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            sys_ack_o   <= 1'b0;
            sys_err_o   <= 1'b0;
            sys_rdata_o <= 32'd0;

            reg_control    <= 32'd0;
            reg_kp         <= 32'd0;
            reg_ki         <= 32'd0;
            reg_setpoint   <= 14'd0;
            reg_sig_gen_1  <= 32'd0;
            reg_sig_gen_2  <= 32'd0;
            reg_sig_gen_3  <= 32'd0;
            reg_output_mux_ch1 <= 3'd0;
            reg_output_mux_ch2 <= 3'd1;
        end else begin
            sys_ack_o <= sys_wen_q | sys_ren_q;
            sys_err_o <= 1'b0;

            // Write
            if (sys_wen_q) begin
                case (sys_addr_q[19:0])
                    20'h00000: reg_control    <= sys_wdata_q;
                    20'h00004: reg_kp         <= sys_wdata_q;
                    20'h00008: reg_ki         <= sys_wdata_q;
                    20'h0000C: reg_setpoint   <= sys_wdata_q[13:0];
                    20'h00010: reg_sig_gen_1  <= sys_wdata_q;
                    20'h00014: reg_sig_gen_2  <= sys_wdata_q;
                    20'h00018: reg_sig_gen_3  <= sys_wdata_q;
                    20'h0001C: ; // Reserved (was noise_cfg)
                    20'h00020: reg_output_mux_ch1 <= sys_wdata_q[2:0];
                    20'h00024: reg_output_mux_ch2 <= sys_wdata_q[2:0];
                    default: ;
                endcase
            end

            // Read
            if (sys_ren_q) begin
                case (sys_addr_q[19:0])
                    20'h00000: sys_rdata_o <= reg_control;
                    20'h00004: sys_rdata_o <= reg_kp;
                    20'h00008: sys_rdata_o <= reg_ki;
                    20'h0000C: sys_rdata_o <= {18'b0, reg_setpoint};
                    20'h00010: sys_rdata_o <= reg_sig_gen_1;
                    20'h00014: sys_rdata_o <= reg_sig_gen_2;
                    20'h00018: sys_rdata_o <= reg_sig_gen_3;
                    20'h0001C: sys_rdata_o <= 32'd0; // Reserved
                    20'h00020: sys_rdata_o <= {29'b0, reg_output_mux_ch1};
                    20'h00024: sys_rdata_o <= {29'b0, reg_output_mux_ch2};
                    20'h00100: sys_rdata_o <= 32'h12345678; // Test register
                    default:   sys_rdata_o <= 32'hDEADBEEF;
                endcase
            end
        end
    end
    
    // =========================================================================
    // Control Bits
    // =========================================================================
    wire global_enable = reg_control[0];
    wire pid_rst_n = rst_n_i & ~reg_control[1];
    wire closed_loop = reg_control[2];
    wire cic_enable = reg_control[3];

    wire signal_model_rst_n = rst_n_i & global_enable;
    wire cic_rst_n = rst_n_i & global_enable;

    // =========================================================================
    // Internal Signals
    // =========================================================================
    wire signed [13:0] disturbance_sig;
    wire signed [13:0] pid_out_wire;

    // =========================================================================
    // 1. Signal Model (Disturbance Generator - sines only, no noise)
    // =========================================================================
    signal_model u_signal_gen (
        .clk(clk_i),
        .rst_n(signal_model_rst_n),
        .gain1_in(reg_sig_gen_1),
        .gain2_in(reg_sig_gen_2),
        .gain3_in(reg_sig_gen_3),
        .disturbance_out(disturbance_sig)
    );

    // =========================================================================
    // 2. DAC Output: disturbance - feedback
    //    In closed-loop mode, the PID feedback is subtracted from the
    //    disturbance. This creates negative feedback: when the PID sees a
    //    positive signal at the ADC (= disturbance - feedback), it increases
    //    feedback, which reduces dac_out, which reduces the ADC reading.
    // =========================================================================
    wire signed [14:0] dac_sum;
    wire signed [13:0] feedback_to_dac;

    assign feedback_to_dac = (global_enable && closed_loop) ? pid_out_wire : 14'sd0;
    assign dac_sum = {disturbance_sig[13], disturbance_sig} - {feedback_to_dac[13], feedback_to_dac};

    // Saturate 15-bit sum to 14-bit signed
    assign dac_out_o = (^dac_sum[14:13]) ? {dac_sum[14], {13{~dac_sum[14]}}} : dac_sum[13:0];

    // =========================================================================
    // 3. ADC Input -> CIC Filter (Decimation)
    //    The real ADC signal (adc_dat_a_i) is used directly as PID input.
    //    It contains disturbance + feedback + real analog noise from the
    //    DAC->cable->ADC path.
    // =========================================================================
    wire        cic_out_valid;
    wire signed [63:0] cic_out_raw;

    cic_filter #(
        .INPUT_WIDTH(14),
        .STAGES(6),
        .DECIMATION(125)
    ) u_cic (
        .clk(clk_i),
        .rst_n(cic_rst_n),
        .d_in(adc_dat_a_q),
        .d_out_valid(cic_out_valid),
        .d_out(cic_out_raw)
    );

    // =========================================================================
    // 4. Scaler (Normalize CIC output back to 14-bit)
    // =========================================================================
    wire        scaler_out_valid;
    wire signed [13:0] scaler_out;

    scaler u_scaler (
        .clk(clk_i),
        .rst_n(cic_rst_n),
        .din_valid(cic_out_valid),
        .din(cic_out_raw),
        .dout_valid(scaler_out_valid),
        .dout(scaler_out)
    );

    // =========================================================================
    // 5. PID Input Mux: CIC path or bypass
    // =========================================================================
    wire signed [13:0] pid_din;
    wire               pid_din_valid;

    assign pid_din       = cic_enable ? scaler_out       : adc_dat_a_q;
    assign pid_din_valid = cic_enable ? scaler_out_valid  : global_enable;

    // =========================================================================
    // 6. PID Controller
    // =========================================================================
    wire pid_out_valid;

    pid_controller u_pid (
        .clk(clk_i),
        .rst_n(pid_rst_n & global_enable),
        .din_valid(pid_din_valid),
        .din(pid_din),
        .kp_in(reg_kp),
        .ki_in(reg_ki),
        .dout_valid(pid_out_valid),
        .dout(pid_out_wire)
    );

    // =========================================================================
    // 7. Output MUX Logic (Independent CH1 / CH2 selection)
    // =========================================================================
    // Signal options:
    //   0: ADC Channel A  (adc_dat_a_q - real ADC input)
    //   1: ADC Channel B  (adc_dat_b_q)
    //   2: Disturbance    (disturbance_sig - from signal model)
    //   3: Feedback/PID   (feedback_to_dac)
    //   4: DAC output     (dac_out_o - disturbance + feedback, what goes to DAC)
    //   5: CIC Filtered   (scaler_out)
    
    reg signed [13:0] mux_ch1;
    reg signed [13:0] mux_ch2;
    
    always_comb begin
        case (reg_output_mux_ch1)
            3'd0: mux_ch1 = adc_dat_a_q;
            3'd1: mux_ch1 = adc_dat_b_q;
            3'd2: mux_ch1 = disturbance_sig;
            3'd3: mux_ch1 = feedback_to_dac;
            3'd4: mux_ch1 = dac_out_o;
            3'd5: mux_ch1 = scaler_out;
            default: mux_ch1 = adc_dat_a_q;
        endcase
    end

    always_comb begin
        case (reg_output_mux_ch2)
            3'd0: mux_ch2 = adc_dat_a_q;
            3'd1: mux_ch2 = adc_dat_b_q;
            3'd2: mux_ch2 = disturbance_sig;
            3'd3: mux_ch2 = feedback_to_dac;
            3'd4: mux_ch2 = dac_out_o;
            3'd5: mux_ch2 = scaler_out;
            default: mux_ch2 = adc_dat_b_q;
        endcase
    end
    
    assign scope_ch1_o = mux_ch1;
    assign scope_ch2_o = mux_ch2;

endmodule
