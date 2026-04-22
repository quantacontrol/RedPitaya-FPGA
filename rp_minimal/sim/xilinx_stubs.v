`timescale 1ns / 1ps
module IBUFDS (input I, input IB, output O); assign O = I; endmodule
module ODDR (output Q, input C, input CE, input D1, input D2, input R, input S); 
    reg q_reg;
    always @(posedge C or posedge R or posedge S) begin
        if (R) q_reg <= 0;
        else if (S) q_reg <= 1;
        else if (CE) q_reg <= D1;
    end
    always @(negedge C or posedge R or posedge S) begin
        if (R) q_reg <= 0;
        else if (S) q_reg <= 1;
        else if (CE) q_reg <= D2;
    end
    assign Q = q_reg;
endmodule
module BUFG (input I, output O); assign O = I; endmodule

module PLLE2_ADV #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter COMPENSATION = "ZHOLD",
    parameter DIVCLK_DIVIDE = 1,
    parameter CLKFBOUT_MULT = 5,
    parameter CLKFBOUT_PHASE = 0.000,
    parameter CLKOUT0_DIVIDE = 1,
    parameter CLKOUT0_PHASE = 0.000,
    parameter CLKOUT0_DUTY_CYCLE = 0.500,
    parameter CLKOUT1_DIVIDE = 1,
    parameter CLKOUT1_PHASE = 0.000,
    parameter CLKOUT1_DUTY_CYCLE = 0.500,
    parameter CLKOUT2_DIVIDE = 1,
    parameter CLKOUT2_PHASE = 0.000,
    parameter CLKOUT2_DUTY_CYCLE = 0.500,
    parameter CLKOUT3_DIVIDE = 1,
    parameter CLKOUT3_PHASE = 0.000,
    parameter CLKOUT3_DUTY_CYCLE = 0.500,
    parameter CLKOUT4_DIVIDE = 1,
    parameter CLKOUT4_PHASE = 0.000,
    parameter CLKOUT4_DUTY_CYCLE = 0.500,
    parameter CLKOUT5_DIVIDE = 1,
    parameter CLKOUT5_PHASE = 0.000,
    parameter CLKOUT5_DUTY_CYCLE = 0.500,
    parameter CLKIN1_PERIOD = 0.000,
    parameter REF_JITTER1 = 0.010
) (
    output CLKFBOUT,
    output CLKOUT0,
    output CLKOUT1,
    output CLKOUT2,
    output CLKOUT3,
    output CLKOUT4,
    output CLKOUT5,
    output LOCKED,
    input  CLKFBIN,
    input  CLKIN1,
    input  CLKIN2,
    input  CLKINSEL,
    input  DCLK,
    input  DEN,
    input  [6:0] DADDR,
    input  [15:0] DI,
    output [15:0] DO,
    output DRDY,
    input  PWRDWN,
    input  RST
);
    // Simple stub for simulation: pass through clk to everything
    // WARNING: This ignores all phase/freq dividers for simulation speed!
    assign CLKFBOUT = CLKIN1;
    assign CLKOUT0  = CLKIN1;
    assign CLKOUT1  = CLKIN1;
    assign CLKOUT2  = CLKIN1; // DAC inverted clk normally, we ignore phase here
    assign CLKOUT3  = CLKIN1;
    assign CLKOUT4  = CLKIN1;
    assign CLKOUT5  = CLKIN1;
    
    // Simulate lock delay
    reg locked_reg;
    initial begin
        locked_reg = 0;
        #100;
        locked_reg = 1;
    end
    always @(posedge RST) begin
        locked_reg = 0;
        #100;
        locked_reg = 1;
    end
    assign LOCKED = locked_reg;
endmodule