#!/bin/bash
# Minimalist Deployment Script for Red Pitaya 125-14

TARGET_IP=$1
if [ -z "$TARGET_IP" ]; then
    echo "Usage: ./deploy.sh <target_ip>"
    exit 1
fi

BITBIN="out/rp_minimal.bit.bin"
DTBO="out/system.dtbo"
RP_PASS="root"

# Check that all required build artifacts exist before touching the board
MISSING=0
if [ ! -f "$BITBIN" ]; then
    echo "ERROR: $BITBIN not found. Run: make hw"
    MISSING=1
fi
if [ ! -f "$DTBO" ]; then
    echo "ERROR: $DTBO not found. Run: make hw"
    MISSING=1
fi
if [ "$MISSING" -eq 1 ]; then
    exit 1
fi

SSH="sshpass -p $RP_PASS ssh -o StrictHostKeyChecking=no root@$TARGET_IP"
SCP="sshpass -p $RP_PASS scp -o StrictHostKeyChecking=no"

echo "--- Step 1: Transferring firmware assets ---"
$SCP "$BITBIN" "$DTBO" root@$TARGET_IP:/tmp/

echo "--- Step 2: Loading Bitstream via fpga_manager ---"
$SSH "mkdir -p /lib/firmware && cp /tmp/rp_minimal.bit.bin /lib/firmware/ && echo 0 > /sys/class/fpga_manager/fpga0/flags && echo rp_minimal.bit.bin > /sys/class/fpga_manager/fpga0/firmware"

echo "--- Step 3: Loading Device Tree Overlay ---"
$SSH "mkdir -p /sys/kernel/config/device-tree/overlays/rp_minimal && cat /tmp/system.dtbo > /sys/kernel/config/device-tree/overlays/rp_minimal/dtbo"

echo "--- Step 4: Restarting Web Backend (Optional) ---"
echo "You may need to manually restart your rust backend or systemd service."
# $SSH "systemctl restart rp-web-scope"

echo "Deployment complete!"
