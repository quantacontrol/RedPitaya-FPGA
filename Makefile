# Red Pitaya 125-14 Lock-in + PID — top-level shortcuts
# All real work happens in rp_minimal/ and rp_web/; this just wires them up.

IP ?=

# ---------------------------------------------------------------------------
# Xilinx tool detection: prefer PATH, fall back to petalinux install
# ---------------------------------------------------------------------------
PETALINUX_DIR ?= $(HOME)/tmp/petalinux
_PETABIN      := $(PETALINUX_DIR)/components/yocto/buildtools/sysroots/x86_64-petalinux-linux/usr/bin

VIVADO  := $(shell which vivado  2>/dev/null)
XSCT    := $(shell which xsct   2>/dev/null || echo $(PETALINUX_DIR)/tools/xsct/bin/xsct)
BOOTGEN := $(shell which bootgen 2>/dev/null || echo $(_PETABIN)/bootgen)
DTC     := $(shell which dtc     2>/dev/null || echo $(_PETABIN)/dtc)

# Verify a tool exists; print a hint and exit if not
define require_tool
	@test -x "$(1)" || { echo "ERROR: '$(2)' not found. $(3)"; exit 1; }
endef

.PHONY: help bitstream fsbl dtbo bit-bin hw sim sim-algo backend frontend web deploy clean setup-venv

help:
	@echo "Targets:"
	@echo "  make setup-venv   # create venv/ and install cocotb deps (run once)"
	@echo "  make sim          # cocotb top-level sim (icarus)"
	@echo "  make sim-algo     # cocotb algorithm sim (verilator)"
	@echo "  make bitstream    # Vivado synth + P&R -> rp_minimal/out/rp_minimal.bit"
	@echo "  make fsbl         # HSI FSBL -> rp_minimal/out/fsbl/executable.elf"
	@echo "  make dtbo         # Device tree overlay -> rp_minimal/out/system.dtbo"
	@echo "  make bit-bin      # Convert .bit to .bit.bin via bootgen"
	@echo "  make hw           # dtbo + bit-bin (skips bitstream/fsbl if already built)"
	@echo "  make backend      # cross-compile Rust backend"
	@echo "  make frontend     # npm run build"
	@echo "  make web          # backend + frontend"
	@echo "  make deploy IP=X  # scp + load onto board"
	@echo "  make clean        # wipe vivado_project and sim_build"

sim:
	$(MAKE) -C rp_minimal/sim

sim-algo:
	$(MAKE) -C modeling/cocotb

bitstream:
	$(call require_tool,$(VIVADO),vivado,Install Vivado and add it to PATH.)
	cd rp_minimal && vivado -mode batch -source build.tcl

fsbl:
	$(call require_tool,$(XSCT),xsct,Ensure petalinux is installed at $(PETALINUX_DIR) or set XSCT=<path>.)
	cd rp_minimal && $(XSCT) build_fsbl_hsi.tcl

dtbo:
	$(call require_tool,$(DTC),dtc,Ensure petalinux is installed at $(PETALINUX_DIR) or set DTC=<path>.)
	@test -f rp_minimal/src/system.dts || { echo "ERROR: rp_minimal/src/system.dts not found."; exit 1; }
	cp rp_minimal/src/system.dts rp_minimal/out/system.dts
	cd rp_minimal/out && $(DTC) -@ -I dts -O dtb -o system.dtbo system.dts

bit-bin:
	$(call require_tool,$(BOOTGEN),bootgen,Ensure petalinux is installed at $(PETALINUX_DIR) or set BOOTGEN=<path>.)
	@test -f rp_minimal/out/rp_minimal.bit || { echo "ERROR: rp_minimal/out/rp_minimal.bit not found. Run: make bitstream"; exit 1; }
	cd rp_minimal && $(BOOTGEN) -image bit_to_bin.bif -arch zynq -process_bitstream bin -w on

# hw: if bitstream/fsbl already exist, skip those steps
hw:
	@if [ ! -f rp_minimal/out/rp_minimal.bit ]; then \
	    echo ">>> rp_minimal.bit not found, running bitstream..."; \
	    $(MAKE) bitstream; \
	else \
	    echo ">>> rp_minimal.bit already exists, skipping bitstream."; \
	fi
	@if [ ! -f rp_minimal/out/fsbl/executable.elf ]; then \
	    echo ">>> fsbl/executable.elf not found, running fsbl..."; \
	    $(MAKE) fsbl; \
	else \
	    echo ">>> fsbl/executable.elf already exists, skipping fsbl."; \
	fi
	$(MAKE) dtbo
	$(MAKE) bit-bin

backend:
	cd rp_web/backend && cross build --release --target armv7-unknown-linux-gnueabihf

frontend:
	cd rp_web/frontend && npm run build

web: backend frontend

deploy:
	@if [ -z "$(IP)" ]; then echo "Usage: make deploy IP=<board-ip>"; exit 1; fi
	cd rp_minimal && ./deploy.sh $(IP)

setup-venv:
	python3.10 -m venv venv
	venv/bin/pip install --upgrade pip
	venv/bin/pip install cocotb cocotb-tools numpy

clean:
	rm -rf rp_minimal/vivado_project rp_minimal/sim/sim_build modeling/cocotb/sim_build
