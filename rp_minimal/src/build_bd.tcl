namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

set design_name ps_system

create_bd_design $design_name
current_bd_design $design_name

# Create interface ports
set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]
set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]
set M_AXI_GP0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI_GP0 ]
set_property -dict [ list \
 CONFIG.ADDR_WIDTH {32} \
 CONFIG.DATA_WIDTH {32} \
 CONFIG.FREQ_HZ {125000000} \
 CONFIG.PROTOCOL {AXI3} \
 ] $M_AXI_GP0

# Create ports
set FCLK_CLK0 [ create_bd_port -dir O -type clk FCLK_CLK0 ]
set FCLK_RESET0_N [ create_bd_port -dir O -type rst FCLK_RESET0_N ]
set M_AXI_GP0_ACLK [ create_bd_port -dir I -type clk -freq_hz 125000000 M_AXI_GP0_ACLK ]
set_property -dict [ list \
 CONFIG.ASSOCIATED_BUSIF {M_AXI_GP0} \
] $M_AXI_GP0_ACLK

# Create instance: proc_sys_reset
set proc_sys_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset ]
set_property -dict [ list \
 CONFIG.C_EXT_RST_WIDTH {1} \
] $proc_sys_reset

# Create instance: processing_system7
set processing_system7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7 ]
set_property -dict [ list \
 CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {125.000000} \
 CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {125.000000} \
 CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {125.000000} \
 CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {100.000000} \
 CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {200.000000} \
 CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
 CONFIG.PCW_CLK0_FREQ {125000000} \
 CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
 CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
 CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
 CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_EN_ENET0 {1} \
 CONFIG.PCW_EN_GPIO {1} \
 CONFIG.PCW_EN_I2C0 {1} \
 CONFIG.PCW_EN_QSPI {1} \
 CONFIG.PCW_EN_SDIO0 {1} \
 CONFIG.PCW_EN_SPI1 {1} \
 CONFIG.PCW_EN_UART0 {1} \
 CONFIG.PCW_EN_UART1 {1} \
 CONFIG.PCW_EN_USB0 {1} \
 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {125} \
 CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
 CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
 CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
 CONFIG.PCW_I2C0_I2C0_IO {MIO 50 .. 51} \
 CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#GPIO#UART 1#UART 1#SPI 1#SPI 1#SPI 1#SPI 1#UART 0#UART 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#USB Reset#GPIO#I2C 0#I2C 0#Enet 0#Enet 0} \
 CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#gpio[7]#tx#rx#mosi#miso#sclk#ss[0]#rx#tx#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#clk#cmd#data[0]#data[1]#data[2]#data[3]#cd#wp#reset#gpio[49]#scl#sda#mdc#mdio} \
 CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 2.5V} \
 CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
 CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
 CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
 CONFIG.PCW_SD0_GRP_CD_IO {MIO 46} \
 CONFIG.PCW_SD0_GRP_WP_ENABLE {1} \
 CONFIG.PCW_SD0_GRP_WP_IO {MIO 47} \
 CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
 CONFIG.PCW_SPI1_GRP_SS0_ENABLE {1} \
 CONFIG.PCW_SPI1_GRP_SS0_IO {MIO 13} \
 CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_SPI1_SPI1_IO {MIO 10 .. 15} \
 CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
 CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_UART1_UART1_IO {MIO 8 .. 9} \
 CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
 CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT {3} \
 CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
 CONFIG.PCW_UIPARAM_DDR_CL {7} \
 CONFIG.PCW_UIPARAM_DDR_COL_ADDR_COUNT {10} \
 CONFIG.PCW_UIPARAM_DDR_CWL {6} \
 CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {4096 MBits} \
 CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
 CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
 CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT {15} \
 CONFIG.PCW_UIPARAM_DDR_SPEED_BIN {DDR3_1066F} \
 CONFIG.PCW_UIPARAM_DDR_T_FAW {40.0} \
 CONFIG.PCW_UIPARAM_DDR_T_RAS_MIN {35.0} \
 CONFIG.PCW_UIPARAM_DDR_T_RC {48.91} \
 CONFIG.PCW_UIPARAM_DDR_T_RCD {7} \
 CONFIG.PCW_UIPARAM_DDR_T_RP {7} \
 CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
 CONFIG.PCW_USB0_RESET_ENABLE {1} \
 CONFIG.PCW_USB0_RESET_IO {MIO 48} \
 CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
 CONFIG.PCW_USE_M_AXI_GP0 {1} \
] $processing_system7

# Create interface connections
connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 [get_bd_intf_ports M_AXI_GP0] [get_bd_intf_pins processing_system7/M_AXI_GP0]
connect_bd_intf_net -intf_net processing_system7_0_ddr [get_bd_intf_ports DDR] [get_bd_intf_pins processing_system7/DDR]
connect_bd_intf_net -intf_net processing_system7_0_fixed_io [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins processing_system7/FIXED_IO]

# Create port connections
connect_bd_net -net m_axi_gp0_aclk_1 [get_bd_ports M_AXI_GP0_ACLK] [get_bd_pins processing_system7/M_AXI_GP0_ACLK]
connect_bd_net -net processing_system7_0_fclk_clk0 [get_bd_ports FCLK_CLK0] [get_bd_pins processing_system7/FCLK_CLK0] [get_bd_pins proc_sys_reset/slowest_sync_clk]
connect_bd_net -net processing_system7_0_fclk_reset0_n [get_bd_ports FCLK_RESET0_N] [get_bd_pins processing_system7/FCLK_RESET0_N] [get_bd_pins proc_sys_reset/ext_reset_in]

# Create address segments
assign_bd_address -offset 0x40000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces processing_system7/Data] [get_bd_addr_segs M_AXI_GP0/Reg] -force

validate_bd_design
save_bd_design
