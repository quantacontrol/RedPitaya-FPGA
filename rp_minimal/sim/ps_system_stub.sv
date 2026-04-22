`timescale 1ns / 1ps
module ps_system (
    input  logic         M_AXI_GP0_ACLK,
    output logic         FCLK_CLK0,
    output logic         FCLK_RESET0_N,
    
    // AXI Master
    output logic [31:0]  M_AXI_GP0_awaddr,
    output logic         M_AXI_GP0_awvalid,
    input  logic         M_AXI_GP0_awready,
    
    output logic [31:0]  M_AXI_GP0_wdata,
    output logic         M_AXI_GP0_wvalid,
    input  logic         M_AXI_GP0_wready,
    
    output logic [31:0]  M_AXI_GP0_araddr,
    output logic         M_AXI_GP0_arvalid,
    input  logic         M_AXI_GP0_arready,
    
    input  logic [31:0]  M_AXI_GP0_rdata,
    input  logic         M_AXI_GP0_rvalid,
    output logic         M_AXI_GP0_rready,
    
    // Dummy standard ports
    inout logic [14:0] DDR_addr,
    inout logic [2:0]  DDR_ba,
    inout logic        DDR_cas_n,
    inout logic        DDR_ck_n,
    inout logic        DDR_ck_p,
    inout logic        DDR_cke,
    inout logic        DDR_cs_n,
    inout logic [3:0]  DDR_dm,
    inout logic [31:0] DDR_dq,
    inout logic [3:0]  DDR_dqs_n,
    inout logic [3:0]  DDR_dqs_p,
    inout logic        DDR_odt,
    inout logic        DDR_ras_n,
    inout logic        DDR_reset_n,
    inout logic        DDR_we_n,
    inout logic [53:0] FIXED_IO_mio,
    inout logic        FIXED_IO_ps_clk,
    inout logic        FIXED_IO_ps_porb,
    inout logic        FIXED_IO_ps_srstb,
    inout logic        FIXED_IO_ddr_vrn,
    inout logic        FIXED_IO_ddr_vrp
);

    // Pass clock through
    assign FCLK_CLK0 = M_AXI_GP0_ACLK;
    
    // Initial reset
    initial begin
        FCLK_RESET0_N = 0;
        #100;
        FCLK_RESET0_N = 1;
    end

endmodule
