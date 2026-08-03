#!/bin/bash
# iMac A1419 firmware setup — WiFi symlinks, NVRAM, BT firmware
set -euo pipefail

FIRMWARE_DIR="/lib/firmware/brcm"

ln -sf "$FIRMWARE_DIR/brcmfmac43602-pcie.bin" \
       "$FIRMWARE_DIR/brcmfmac43602-pcie.Apple Inc.-iMac17,1.bin"

# NOTE: No clm_blob or txcap_blob symlink!
# ap.bin is AP firmware, NOT a CLM blob. Symlinking it as clm_blob
# causes "clmload failed (-52)" and crashes the WiFi dongle.
# BCM43602 has no CLM blob in linux-firmware — driver works without it
# (logs harmless "no clm_blob/txcap_blob available" warnings, limited channels).

if [ ! -f "$FIRMWARE_DIR/brcmfmac43602-pcie.txt" ]; then
    echo "WARNING: brcmfmac43602-pcie.txt not found — WiFi may not work"
fi

if [ -f "$FIRMWARE_DIR/BCM20703A1-05ac-8294.hcd" ]; then
    ln -sf "$FIRMWARE_DIR/BCM20703A1-05ac-8294.hcd" \
           "$FIRMWARE_DIR/BCM-05ac-8294.hcd"
else
    echo "WARNING: BCM20703A1-05ac-8294.hcd not found — BT may not work"
fi
