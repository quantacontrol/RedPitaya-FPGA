import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# from cocotb.binary import BinaryValue # Removed in Cocotb 2.0
import numpy as np

# AXI Register Map
REG_CONTROL = 0x00
REG_KP = 0x04
REG_KI = 0x08
REG_SETPOINT = 0x0C
REG_SIG_GEN_1 = 0x10
REG_SIG_GEN_2 = 0x14
REG_SIG_GEN_3 = 0x18
REG_OUT_MUX_CH1 = 0x20
REG_OUT_MUX_CH2 = 0x24


class MinimalRedPitaya:
    def __init__(self, dut):
        self.dut = dut

        # Start clocks
        # We need to assign clock bit by bit, but since packed arrays are tricky in Icarus/Cocotb,
        # let's just toggle the whole port.
        # Actually it's easier to create a simple coroutine to toggle the packed clock port
        cocotb.start_soon(self.clock_gen())

        # PS clock (FCLK0) is also 125MHz
        cocotb.start_soon(Clock(dut.fclk_clk0, 8, units="ns").start())

    async def clock_gen(self):
        """Generate differential clock on packed 2-bit port"""
        self.dut.adc_clk_i.value = 1  # [1]=0 (P), [0]=1 (N)
        while True:
            await Timer(4, units="ns")
            self.dut.adc_clk_i.value = 2  # [1]=1 (P), [0]=0 (N)
            await Timer(4, units="ns")
            self.dut.adc_clk_i.value = 1  # [1]=0 (P), [0]=1 (N)

    async def reset(self):
        self.dut.fclk_rstn.value = 0
        self.dut.adc_dat_i.value = 0

        # AXI init
        self.dut.axi_awvalid.value = 0
        self.dut.axi_wvalid.value = 0
        self.dut.axi_arvalid.value = 0

        await Timer(100, units="ns")
        self.dut.fclk_rstn.value = 1
        await Timer(100, units="ns")

        # Wait for PLL to lock (simulated)
        self.dut.pll_locked.value = 1
        await Timer(50, units="ns")

    async def axi_write(self, addr, data):
        # The base address in feedback_controller_top is 0x40900000
        # The PS stub just passes the raw address through to the AXI interconnect,
        # but in our top.sv, feedback_controller_top's sys_addr_i expects the lower 20 bits or similar
        # Wait, let's see how top.sv connects it. It just passes axi_awaddr.
        # But feedback_controller_top case statement expects `case (sys_addr_i[19:0])`
        # and doesn't check the base address. So any address matching the lower 20 bits works.
        self.dut.axi_awaddr.value = addr
        self.dut.axi_wdata.value = data
        self.dut.axi_awvalid.value = 1
        self.dut.axi_wvalid.value = 1

        # Wait for AWREADY and WREADY
        while True:
            await RisingEdge(self.dut.fclk_clk0)
            if self.dut.axi_awready.value == 1 and self.dut.axi_wready.value == 1:
                break

        self.dut.axi_awvalid.value = 0
        self.dut.axi_wvalid.value = 0
        await RisingEdge(self.dut.fclk_clk0)

    def val_to_adc(self, val):
        """Convert signed 14-bit integer to the format the Red Pitaya ADC sends"""
        # Limit to 14 bits signed
        if val > 8191:
            val = 8191
        if val < -8192:
            val = -8192

        # The ADC sends data as inverted offset binary (negative slope)
        # We need to reverse what the top.sv does:
        # adc_dat_a <= {adc_dat_raw[0][ADW-1], ~adc_dat_raw[0][ADW-2:0]};

        bin_val = val & 0x3FFF
        sign_bit = (bin_val >> 13) & 1
        data_bits = bin_val & 0x1FFF

        adc_raw = (sign_bit << 13) | (~data_bits & 0x1FFF)
        return adc_raw << 2  # Shift up to 16 bits (ADC data is on top 14 bits)

    def dac_to_val(self, dac_raw):
        """Convert DAC output format back to signed 14-bit integer"""
        # top.sv does: dac_dat_a_reg <= {dac_a[13], ~dac_a[12:0]};
        sign_bit = (dac_raw >> 13) & 1
        data_bits = dac_raw & 0x1FFF

        val = (sign_bit << 13) | (~data_bits & 0x1FFF)
        if sign_bit:
            val = val - 16384
        return val


@cocotb.test()
async def test_full_chain(dut):
    """Test the full ADC -> Algorithm -> DAC chain"""
    rp = MinimalRedPitaya(dut)

    # 1. Reset system
    await rp.reset()

    # 2. Configure algorithm via AXI
    # Enable global, open loop (mode 0)
    await rp.axi_write(REG_CONTROL, 1)

    # Configure signal generator 3 (1200Hz, large amplitude) which is much faster!
    # gain3 is at 0x18
    await rp.axi_write(REG_SIG_GEN_3, int(1.0 * (1 << 16)))  # Gain 1.0 (Q16.16)

    # 3. Simulate ADC input and observe DAC output
    # We will feed a 0 DC signal into ADC.
    # Because we enabled sig gen 3, the DAC should output a sine wave!

    # Pack the two 16-bit ADC values into one 32-bit port (since it's an array of 2 elements, [2-1:0] [16-1:0])
    # The format is {adc_dat_i[1], adc_dat_i[0]}
    zero_val = rp.val_to_adc(0)
    rp.dut.adc_dat_i.value = (zero_val << 16) | zero_val

    # Wait for the sine wave to develop (it takes some time for the signal generator to start)
    # The sine generator runs at ~125MHz / 2^24. So 0.5Hz might take very long to see in sim!
    # Let's write a higher frequency to sig gen 1 to see it quickly in 1000 samples.
    # At 125MHz, 1000 samples = 8us. To see a full wave in 8us, frequency should be ~125kHz.
    # Phase step = (125kHz / 125MHz) * 2^24 ≈ 16777.
    # Let's just set the gain to a moderate value and write a fast frequency test register instead.
    # Wait, the frequency is fixed in signal_model.sv. Let's see what signal_model.sv does.
    # Oh! The signal_model just accumulates phase. If we want to see it, maybe we should just
    # read more samples, or check the AXI read to ensure our write worked!

    # Read back control register to verify AXI works
    rp.dut.axi_araddr.value = REG_CONTROL
    rp.dut.axi_arvalid.value = 1

    while True:
        await RisingEdge(rp.dut.fclk_clk0)
        if rp.dut.axi_arready.value == 1:
            break

    rp.dut.axi_arvalid.value = 0

    while True:
        await RisingEdge(rp.dut.fclk_clk0)
        if rp.dut.axi_rvalid.value == 1:
            ctrl_read = rp.dut.axi_rdata.value.integer
            break

    dut._log.info(f"Read back control register: {ctrl_read}")

    dac_values = []

    # Let's read 100000 samples to give it time to go negative (1200Hz = 833us = 104k samples at 125MHz)
    for i in range(120000):
        await RisingEdge(dut.adc_clk)

        # dac_dat_o can have 'x' or 'z' during early startup
        dac_val_str = dut.dac_dat_o.value.binstr
        if "x" in dac_val_str or "z" in dac_val_str:
            continue

        dac_val = rp.dac_to_val(int(dac_val_str, 2))
        dac_values.append(dac_val)

    # Check if the DAC output is oscillating (not just flat 0)
    max_val = max(dac_values)
    min_val = min(dac_values)

    dut._log.info(f"DAC output range: {min_val} to {max_val}")

    assert max_val > 1000, "DAC did not generate expected positive sine amplitude"
    assert min_val < -1000, "DAC did not generate expected negative sine amplitude"

    dut._log.info("Full chain test passed! The minimal framework is functional.")
