#
# Authors: Matej Oblak, Iztok Jeras
# (C) Red Pitaya 2013-2015
#
# Red Pitaya FPGA/SoC Makefile
#
# Produces:
#   3. FPGA bit file.
#   1. FSBL (First stage bootloader) ELF binary.
#   2. Memtest (stand alone memory test) ELF binary.
#   4. Linux device tree source (dts).

PRJ   ?= v0.94
#PRJ   ?= stream_app
# MODEL ?= Z20_G2
MODEL ?= Z10
HWID  ?= ""
DEFINES ?= ""
DTS_VER ?= 2024.2
VIVADO_OPTS ?=
XSCT ?= /home/lamuguo/tools/Xilinx/PetaLinux/2024.2/bin/components/xsct/bin/xsct

# Red Pitaya SSH deployment settings
RP_HOST ?= root@rp-f0edec.local
RP_MODEL ?= z10_125
RP_FPGAUTIL = /opt/redpitaya/bin/fpgautil
RP_OVERLAY  = /opt/redpitaya/sbin/overlay.sh

# build artefacts
FPGA_BIT    = prj/$(PRJ)/out/red_pitaya.bit
FPGA_BIN    = prj/$(PRJ)/out/red_pitaya.bit.bin
FSBL_ELF    = prj/$(PRJ)/sdk/fsbl/executable.elf
MEMTEST_ELF = prj/$(PRJ)/sdk/dram_test/executable.elf
DEVICE_TREE = prj/$(PRJ)/sdk/dts/system.dts

# Vivado from Xilinx provides IP handling, FPGA compilation
# hsi (hardware software interface) provides software integration
# both tools are run in batch mode with an option to avoid log/journal files
VIVADO = vivado -nojournal -mode batch
HSI    = hsi    -nolog -nojournal -mode batch
BOOTGEN= bootgen -image prj/$(PRJ)/out/red_pitaya.bif -arch zynq -process_bitstream bin
#HSI    = hsi    -nolog -mode batch

.PHONY: all clean project sim program deploy deploy-reboot sdimage sdimage-download rp-web-build

all: $(FPGA_BIT) $(FSBL_ELF) $(DEVICE_TREE) $(FPGA_BIN)

# TODO: clean should go into each project
clean:
	rm -rf out .Xil .srcs sdk project sim
	rm -rf prj/$(PRJ)/out prj/$(PRJ)/.Xil prj/$(PRJ)/.srcs prj/$(PRJ)/sdk prj/$(PRJ)/project

sim: 
	vivado -source red_pitaya_vivado_sim.tcl -tclargs $(PRJ) $(MODEL) $(DEFINES)

# WARNING: 'make program' programs via JTAG while Linux is running, which
# causes the AXI bus to hang and triggers the watchdog reboot. Use 'make deploy'
# instead for safe runtime reprogramming via SSH.
program:
	vivado -nojournal -nolog -mode batch -source program_fpga.tcl -tclargs $(FPGA_BIT)

# Safe runtime FPGA update via SSH (no reboot needed).
# Loads the bitstream via fpga_manager sysfs in the background (nohup),
# because writing to the firmware sysfs node briefly disrupts the AXI bus
# and drops the SSH connection. We reconnect after ~5s to verify success.
deploy: $(FPGA_BIN)
	@echo "Copying $(FPGA_BIN) to $(RP_HOST)..."
	scp $(FPGA_BIN) $(RP_HOST):/tmp/red_pitaya.bit.bin
	@echo "Launching FPGA programming in background..."
	-ssh $(RP_HOST) ' \
	    rmdir /configfs/device-tree/overlays/Full 2>/dev/null || true; \
	    echo 0 > /sys/class/fpga_manager/fpga0/flags; \
	    cp /tmp/red_pitaya.bit.bin /lib/firmware/red_pitaya_custom.bit.bin; \
	    nohup sh -c "echo red_pitaya_custom.bit.bin > /sys/class/fpga_manager/fpga0/firmware" \
	        > /tmp/fpga_deploy.log 2>&1 &'
	@echo "Waiting for FPGA to finish programming..."
	@sleep 5
	@echo "Verifying FPGA state..."
	@ssh $(RP_HOST) 'state=$$(cat /sys/class/fpga_manager/fpga0/state); \
	    echo "FPGA state: $$state"; \
	    cat /tmp/fpga_deploy.log 2>/dev/null; \
	    [ "$$state" = "operating" ]'
	@echo "Done. FPGA reprogrammed successfully."

# Persist the bitstream to /boot/fpga so it survives reboots, then reboot.
deploy-reboot: $(FPGA_BIN)
	@echo "Copying $(FPGA_BIN) to $(RP_HOST):/opt/redpitaya/fpga/$(RP_MODEL)/$(PRJ)/fpga.bit.bin ..."
	scp $(FPGA_BIN) $(RP_HOST):/opt/redpitaya/fpga/$(RP_MODEL)/$(PRJ)/fpga.bit.bin
	@echo "Rebooting Red Pitaya..."
	ssh $(RP_HOST) 'reboot' || true
	@echo "Device is rebooting. Wait ~30s then reconnect."

project:
ifneq ($(HWID),"")
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_project_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID)
else
	vivado $(VIVADO_OPTS) -source red_pitaya_vivado_project_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES)
endif

$(FPGA_BIT):
ifneq ($(HWID),"")
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES) HWID=$(HWID)
else
	$(VIVADO) -source red_pitaya_vivado_$(MODEL).tcl -tclargs $(PRJ) $(DEFINES)
endif
	./synCheck.sh

$(FSBL_ELF): $(FPGA_BIT)
	$(XSCT) red_pitaya_hsi_fsbl.tcl $(PRJ)
	./modeling/fix_and_build_fsbl.sh $(PRJ)

$(DEVICE_TREE): $(FPGA_BIT)
	$(XSCT) red_pitaya_hsi_dts.tcl  $(PRJ) DTS_VER=$(DTS_VER)

$(FPGA_BIN): $(FPGA_BIT)
	@echo all:{$(FPGA_BIT)} > prj/$(PRJ)/out/red_pitaya.bif
	$(BOOTGEN)

# ---------- rp-web-scope (Rust backend + Vue frontend) ----------

RP_WEB_DIR     = rp_web
RP_WEB_DEPLOY  = $(RP_WEB_DIR)/deploy
RP_WEB_BINARY  = $(RP_WEB_DEPLOY)/rp-web-scope

# Build rp-web-scope for ARM (cross-compile backend + build frontend)
rp-web-build:
	@echo "=== Building rp-web-scope ==="
	cd $(RP_WEB_DIR)/backend && cross build --release --target armv7-unknown-linux-gnueabihf
	cd $(RP_WEB_DIR)/frontend && npm run build
	@mkdir -p $(RP_WEB_DEPLOY)/frontend
	cp $(RP_WEB_DIR)/target/armv7-unknown-linux-gnueabihf/release/backend $(RP_WEB_DEPLOY)/rp-web-scope
	cp -r $(RP_WEB_DIR)/frontend/dist $(RP_WEB_DEPLOY)/frontend/
	@printf '[Unit]\nDescription=Red Pitaya Web Scope\nAfter=network.target\n\n[Service]\nType=simple\nWorkingDirectory=/opt/rp-web-scope\nEnvironment=FRONTEND_PATH=/opt/rp-web-scope/frontend/dist\nExecStart=/opt/rp-web-scope/rp-web-scope\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' > $(RP_WEB_DEPLOY)/rp-web-scope.service
	@echo "=== rp-web-scope build complete: $(RP_WEB_DEPLOY)/ ==="

# ---------- SD Card Image ----------

# Build SD card image from existing build artifacts.
# Requires: FPGA built (make), rp-web-scope built (make rp-web-build),
#           and a base Red Pitaya OS image.
# Usage:
#   make sdimage BASE_IMAGE=/path/to/rp-os.img
#   BASE_IMAGE=/path/to/rp-os.img make sdimage
sdimage: $(FPGA_BIN)
	@if [ ! -f "$(RP_WEB_BINARY)" ]; then \
		echo "ERROR: rp-web-scope not built. Run 'make rp-web-build' first."; \
		exit 1; \
	fi
	PRJ=$(PRJ) MODEL=$(MODEL) BASE_IMAGE=$(BASE_IMAGE) \
		./scripts/build_sdcard_image.sh

# Download the base image and then build the SD card image.
sdimage-download: $(FPGA_BIN)
	@if [ ! -f "$(RP_WEB_BINARY)" ]; then \
		echo "ERROR: rp-web-scope not built. Run 'make rp-web-build' first."; \
		exit 1; \
	fi
	PRJ=$(PRJ) MODEL=$(MODEL) BASE_IMAGE=$(BASE_IMAGE) \
		./scripts/build_sdcard_image.sh --download
