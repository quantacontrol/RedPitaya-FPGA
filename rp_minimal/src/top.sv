`timescale 1ns / 1ps

module top (
  // PS connections
  inout  logic [54-1:0] FIXED_IO_mio     ,
  inout  logic          FIXED_IO_ps_clk  ,
  inout  logic          FIXED_IO_ps_porb ,
  inout  logic          FIXED_IO_ps_srstb,
  inout  logic          FIXED_IO_ddr_vrn ,
  inout  logic          FIXED_IO_ddr_vrp ,
  // DDR
  inout  logic [15-1:0] DDR_addr   ,
  inout  logic [ 3-1:0] DDR_ba     ,
  inout  logic          DDR_cas_n  ,
  inout  logic          DDR_ck_n   ,
  inout  logic          DDR_ck_p   ,
  inout  logic          DDR_cke    ,
  inout  logic          DDR_cs_n   ,
  inout  logic [ 4-1:0] DDR_dm     ,
  inout  logic [32-1:0] DDR_dq     ,
  inout  logic [ 4-1:0] DDR_dqs_n  ,
  inout  logic [ 4-1:0] DDR_dqs_p  ,
  inout  logic          DDR_odt    ,
  inout  logic          DDR_ras_n  ,
  inout  logic          DDR_reset_n,
  inout  logic          DDR_we_n   ,

  // ADC
  input  logic [ 2-1:0] [16-1:0] adc_dat_i,  // ADC data
  input  logic          [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
  output logic          [ 2-1:0] adc_clk_o,  // optional ADC clock source
  output logic                   adc_cdcs_o, // ADC clock duty cycle stabilizer
  
  // DAC
  output logic [ 14-1:0] dac_dat_o  ,  // DAC combined data
  output logic           dac_wrt_o  ,  // DAC write
  output logic           dac_sel_o  ,  // DAC channel select
  output logic           dac_clk_o  ,  // DAC clock
  output logic           dac_rst_o  ,  // DAC reset
  
  // PWM DAC
  output logic [  4-1:0] dac_pwm_o  ,  // 1-bit PWM DAC
  
  // XADC
  input  logic [  5-1:0] vinp_i     ,  // voltages p
  input  logic [  5-1:0] vinn_i     ,  // voltages n
  
  // Expansion connector
  inout  logic [  8-1:0] exp_p_io   ,
  inout  logic [  8-1:0] exp_n_io   ,
  
  // SATA connector
  output logic [  2-1:0] daisy_p_o  ,
  output logic [  2-1:0] daisy_n_o  ,
  input  logic [  2-1:0] daisy_p_i  ,
  input  logic [  2-1:0] daisy_n_i  ,

  // LED
  output logic [  8-1:0] led_o
);

//---------------------------------------------------------------------------------
// Zynq PS Signals
//---------------------------------------------------------------------------------
logic fclk_clk0;
logic fclk_rstn;
logic [31:0] axi_awaddr, axi_araddr, axi_wdata, axi_rdata;
logic [3:0]  axi_awid, axi_arid;
logic [3:0]  axi_awlen, axi_arlen;
logic [2:0]  axi_awsize, axi_arsize;
logic [1:0]  axi_awburst, axi_arburst;
logic [3:0]  axi_awcache, axi_arcache;
logic [2:0]  axi_awprot, axi_arprot;
logic        axi_awvalid, axi_awready;
logic        axi_wvalid, axi_wready, axi_wlast;
logic [3:0]  axi_wstrb;
logic        axi_bvalid, axi_bready;
logic [1:0]  axi_bresp;
logic [3:0]  axi_bid;
logic        axi_arvalid, axi_arready;
logic        axi_rvalid, axi_rready, axi_rlast;
logic [1:0]  axi_rresp;
logic [3:0]  axi_rid;

ps_system ps_i (
  .DDR_addr          (DDR_addr),
  .DDR_ba            (DDR_ba),
  .DDR_cas_n         (DDR_cas_n),
  .DDR_ck_n          (DDR_ck_n),
  .DDR_ck_p          (DDR_ck_p),
  .DDR_cke           (DDR_cke),
  .DDR_cs_n          (DDR_cs_n),
  .DDR_dm            (DDR_dm),
  .DDR_dq            (DDR_dq),
  .DDR_dqs_n         (DDR_dqs_n),
  .DDR_dqs_p         (DDR_dqs_p),
  .DDR_odt           (DDR_odt),
  .DDR_ras_n         (DDR_ras_n),
  .DDR_reset_n       (DDR_reset_n),
  .DDR_we_n          (DDR_we_n),
  .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
  .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
  .FIXED_IO_mio      (FIXED_IO_mio),
  .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
  .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
  .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
  
  .FCLK_CLK0         (fclk_clk0),
  .FCLK_RESET0_N     (fclk_rstn),
  .M_AXI_GP0_ACLK    (fclk_clk0),
  
  .M_AXI_GP0_awaddr  (axi_awaddr),
  .M_AXI_GP0_awvalid (axi_awvalid),
  .M_AXI_GP0_awready (axi_awready),
  .M_AXI_GP0_araddr  (axi_araddr),
  .M_AXI_GP0_arvalid (axi_arvalid),
  .M_AXI_GP0_arready (axi_arready),
  .M_AXI_GP0_rdata   (axi_rdata),
  .M_AXI_GP0_rvalid  (axi_rvalid),
  .M_AXI_GP0_wdata   (axi_wdata),
  .M_AXI_GP0_wready  (axi_wready),
  .M_AXI_GP0_wvalid  (axi_wvalid)
);

// We stub the AXI for now or connect to dummy
assign axi_awready = 1'b1;
assign axi_wready  = 1'b1;
assign axi_arready = 1'b1;
assign axi_rvalid  = 1'b1;


//---------------------------------------------------------------------------------
// Clock and PLL
//---------------------------------------------------------------------------------
logic adc_clk_in;
logic pll_adc_clk, pll_dac_clk_1x, pll_dac_clk_2x, pll_dac_clk_2p;
logic pll_ser_clk, pll_pwm_clk, pll_locked;
logic adc_clk, dac_clk_1x, dac_clk_2x, dac_clk_2p;
logic rstn_pll;

IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));

assign rstn_pll = fclk_rstn;

red_pitaya_pll pll_i (
  .clk         (adc_clk_in),     // clock
  .rstn        (rstn_pll),       // reset - active low
  .clk_adc     (pll_adc_clk),    // ADC clock (125 MHz)
  .clk_dac_1x  (pll_dac_clk_1x), // DAC clock 125MHz
  .clk_dac_2x  (pll_dac_clk_2x), // DAC clock 250MHz
  .clk_dac_2p  (pll_dac_clk_2p), // DAC clock 250MHz -45DGR
  .clk_ser     (pll_ser_clk),    // fast serial clock
  .clk_pdm     (pll_pwm_clk),    // PWM clock
  .pll_locked  (pll_locked)
);

BUFG bufg_adc_clk    (.O(adc_clk),    .I(pll_adc_clk));
BUFG bufg_dac_clk_1x (.O(dac_clk_1x), .I(pll_dac_clk_1x));
BUFG bufg_dac_clk_2x (.O(dac_clk_2x), .I(pll_dac_clk_2x));
BUFG bufg_dac_clk_2p (.O(dac_clk_2p), .I(pll_dac_clk_2p));

logic adc_rstn, dac_rst;
always_ff @(posedge adc_clk) adc_rstn <= pll_locked;
always_ff @(posedge dac_clk_1x) dac_rst <= ~pll_locked;

//---------------------------------------------------------------------------------
// ADC Data Capture
//---------------------------------------------------------------------------------
localparam ADW = 14;
logic signed [ADW-1:0] adc_dat_a, adc_dat_b;
logic [ADW-1:0] adc_dat_raw [1:0];

assign adc_dat_raw[0] = adc_dat_i[0][15 -: ADW];
assign adc_dat_raw[1] = adc_dat_i[1][15 -: ADW];

// Convert negative slope to two's complement
always_ff @(posedge adc_clk) begin
  adc_dat_a <= {adc_dat_raw[0][ADW-1], ~adc_dat_raw[0][ADW-2:0]};
  adc_dat_b <= {adc_dat_raw[1][ADW-1], ~adc_dat_raw[1][ADW-2:0]};
end

// Duty cycle stabilizer
assign adc_cdcs_o = 1'b1;
ODDR i_adc_clk_p ( .Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));
ODDR i_adc_clk_n ( .Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));

//---------------------------------------------------------------------------------
// Algorithm Core (Modeling) Integration
//---------------------------------------------------------------------------------
wire signed [13:0] fbc_dac_out;
wire signed [13:0] fbc_scope_ch1;
wire signed [13:0] fbc_scope_ch2;

feedback_controller_top fbc_i (
    .clk_i      (adc_clk),
    .rst_n_i    (adc_rstn),
    
    // AXI4-Lite style interface connected to dummy PS signals for now
    .sys_addr_i (axi_awvalid ? axi_awaddr : axi_araddr),
    .sys_wdata_i(axi_wdata),
    .sys_wen_i  (axi_awvalid & axi_wvalid),
    .sys_ren_i  (axi_arvalid),
    .sys_rdata_o(axi_rdata), // Connects back to PS
    .sys_err_o  (),
    .sys_ack_o  (),
    
    // Physical Signals
    .adc_dat_a_i(adc_dat_a),
    .adc_dat_b_i(adc_dat_b),
    .dac_out_o  (fbc_dac_out),
    .scope_ch1_o(fbc_scope_ch1),
    .scope_ch2_o(fbc_scope_ch2)
);

//---------------------------------------------------------------------------------
// DAC Output
//---------------------------------------------------------------------------------
logic signed [13:0] dac_a, dac_b;
logic [13:0] dac_dat_a_reg, dac_dat_b_reg;

// Connect Feedback Controller output to DAC Channel A
assign dac_a = fbc_dac_out; 
assign dac_b = 14'sd0;

always_ff @(posedge dac_clk_1x) begin
  // Convert two's complement to negative slope for DAC
  dac_dat_a_reg <= {dac_a[13], ~dac_a[12:0]};
  dac_dat_b_reg <= {dac_b[13], ~dac_b[12:0]};
end

ODDR oddr_dac_clk          (.Q(dac_clk_o), .D1(1'b0),          .D2(1'b1),          .C(dac_clk_2p), .CE(1'b1), .R(1'b0),   .S(1'b0));
ODDR oddr_dac_wrt          (.Q(dac_wrt_o), .D1(1'b0),          .D2(1'b1),          .C(dac_clk_2x), .CE(1'b1), .R(1'b0),   .S(1'b0));
ODDR oddr_dac_sel          (.Q(dac_sel_o), .D1(1'b1),          .D2(1'b0),          .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
ODDR oddr_dac_rst          (.Q(dac_rst_o), .D1(dac_rst),       .D2(dac_rst),       .C(dac_clk_1x), .CE(1'b1), .R(1'b0),   .S(1'b0));

genvar i;
generate
  for (i = 0; i < 14; i = i + 1) begin : dac_oddr
    ODDR oddr_dac_dat (.Q(dac_dat_o[i]), .D1(dac_dat_b_reg[i]), .D2(dac_dat_a_reg[i]), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
  end
endgenerate

//---------------------------------------------------------------------------------
// Stubs for unconnected outputs
//---------------------------------------------------------------------------------
assign dac_pwm_o = 4'b0;
assign led_o = 8'hAA;

assign exp_p_io = 8'bz;
assign exp_n_io = 8'bz;

assign daisy_p_o = 2'b0;
assign daisy_n_o = 2'b0;

endmodule
