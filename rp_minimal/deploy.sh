#!/bin/bash
# Minimalist Deployment Script for Red Pitaya 125-14

TARGET_IP=$1
if [ -z "$TARGET_IP" ]; then
    echo "Usage: ./deploy.sh <target_ip>"
    exit 1
fi

echo "--- Step 1: Transferring firmware assets ---"
scp out/rp_minimal.bit.bin out/system.dtbo root@$TARGET_IP:/tmp/

echo "--- Step 2: Loading Bitstream via fpga_manager ---"
ssh root@$TARGET_IP "mkdir -p /lib/firmware && cp /tmp/rp_minimal.bit.bin /lib/firmware/ && echo 0 > /sys/class/fpga_manager/fpga0/flags && echo rp_minimal.bit.bin > /sys/class/fpga_manager/fpga0/firmware"

echo "--- Step 3: Loading Device Tree Overlay ---"
ssh root@$TARGET_IP "mkdir -p /sys/kernel/config/device-tree/overlays/rp_minimal && cat /tmp/system.dtbo > /sys/kernel/config/device-tree/overlays/rp_minimal/dtbo"

echo "--- Step 4: Restarting Web Backend (Optional) ---"
echo "You may need to manually restart your rust backend or systemd service."
# ssh root@$TARGET_IP "systemctl restart rp-web-scope"

echo "Deployment complete!"
