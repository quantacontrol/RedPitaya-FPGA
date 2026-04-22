import os
import sys
from pathlib import Path
from cocotb.runner import get_runner


def test_top():
    # Source directory for rp_minimal
    src_dir = Path(__file__).parent.parent / "src"

    # Core modeling directory
    modeling_dir = Path(__file__).parent.parent.parent / "modeling" / "rtl"

    # Collect source files
    verilog_sources = [
        # Minimal top and PLL
        src_dir / "top.sv",
        src_dir / "red_pitaya_pll.sv",
        # Modeling core (dependencies first)
        modeling_dir / "cic_filter.sv",
        modeling_dir / "pid_controller.sv",
        modeling_dir / "prng.sv",
        modeling_dir / "scaler.sv",
        modeling_dir / "sine_lut.sv",
        modeling_dir / "sine_gen.sv",
        modeling_dir / "signal_model.sv",
        modeling_dir / "feedback_controller_top.sv",
    ]

    # We need to simulate the ps_system stub since we don't have the block design in pure Verilog sim
    # Let's create a quick stub file for simulation
    stub_file = Path(__file__).parent / "ps_system_stub.sv"
    with open(stub_file, "w") as f:
        f.write("""
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
""")

    verilog_sources.append(stub_file)

    # Need IBUFDS, ODDR, BUFG stubs for pure Verilog sim (since these are Xilinx primitives)
    xilinx_stubs = Path(__file__).parent / "xilinx_stubs.v"
    with open(xilinx_stubs, "w") as f:
        f.write("""
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
""")
    verilog_sources.append(xilinx_stubs)

    sim = os.getenv("SIM", "icarus")
    runner = get_runner(sim)

    runner.build(
        verilog_sources=verilog_sources,
        hdl_toplevel="top",
        always=True,
    )

    runner.test(
        hdl_toplevel="top",
        test_module="test_top",
    )


if __name__ == "__main__":
    test_top()
