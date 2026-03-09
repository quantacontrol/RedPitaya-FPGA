#!/bin/bash
PRJ=$1

# Define compiler settings
ARM_CC="arm-none-eabi-gcc"
ARM_CC_FLAGS="-c -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -DXPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ=666666687"
ARM_AR="arm-none-eabi-ar"

# Patch Makefiles that use COMPILER= pattern
find prj/$PRJ/sdk/fsbl -name Makefile -exec sed -i "s|^COMPILER=\$|COMPILER=${ARM_CC} ${ARM_CC_FLAGS}|" {} +
find prj/$PRJ/sdk/fsbl -name Makefile -exec sed -i "s|^ARCHIVER=\$|ARCHIVER=${ARM_AR}|" {} +

# Patch standalone Makefile which uses CC=$(COMPILER) pattern
# Need to add COMPILER definition since it's not defined but referenced
STANDALONE_MK="prj/$PRJ/sdk/fsbl/zynq_fsbl_bsp/ps7_cortexa9_0/libsrc/standalone_v9_2/src/Makefile"
if [ -f "$STANDALONE_MK" ]; then
    # Add COMPILER definition at the beginning of the file after include config.make
    sed -i "/^include config.make/a COMPILER=${ARM_CC} ${ARM_CC_FLAGS}" "$STANDALONE_MK"
    sed -i "s|^AR=\$(ARCHIVER)|AR=${ARM_AR}|" "$STANDALONE_MK"
fi

# Patch top-level FSBL Makefile
sed -i "s/^CC :=/CC := ${ARM_CC}/" prj/$PRJ/sdk/fsbl/Makefile
sed -i 's/^CC_FLAGS := .*/CC_FLAGS := -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -DXPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ=666666687 -MMD -MP/' prj/$PRJ/sdk/fsbl/Makefile

# Patch BSP Makefile archive command
sed -i "s| -r | ${ARM_AR} -r |" prj/$PRJ/sdk/fsbl/zynq_fsbl_bsp/Makefile

# Silence spurious warnings from Xilinx-generated Makefiles (dep file includes)
find prj/$PRJ/sdk/fsbl -name Makefile -exec sed -i 's/^include \$(wildcard/-include $(wildcard/g' {} +

# Build
make -C prj/$PRJ/sdk/fsbl/zynq_fsbl_bsp all
make -C prj/$PRJ/sdk/fsbl all
