SIM ?= icarus
TOPLEVEL_LANG ?= verilog

PWD=$(shell pwd)
MODELING_DIR=$(PWD)/../../modeling/rtl
SRC_DIR=$(PWD)/../src

VERILOG_SOURCES = $(SRC_DIR)/top.sv
VERILOG_SOURCES += $(SRC_DIR)/red_pitaya_pll.sv
VERILOG_SOURCES += $(MODELING_DIR)/cic_filter.sv
VERILOG_SOURCES += $(MODELING_DIR)/pid_controller.sv
VERILOG_SOURCES += $(MODELING_DIR)/prng.sv
VERILOG_SOURCES += $(MODELING_DIR)/scaler.sv
VERILOG_SOURCES += $(MODELING_DIR)/sine_lut.sv
VERILOG_SOURCES += $(MODELING_DIR)/sine_gen.sv
VERILOG_SOURCES += $(MODELING_DIR)/signal_model.sv
VERILOG_SOURCES += $(MODELING_DIR)/feedback_controller_top.sv
VERILOG_SOURCES += $(PWD)/ps_system_stub.sv
VERILOG_SOURCES += $(PWD)/xilinx_stubs.v

TOPLEVEL = top
MODULE = test_top

include $(shell cocotb-config --makefiles)/Makefile.sim
