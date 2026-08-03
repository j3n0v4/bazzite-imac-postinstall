#!/bin/bash
# bazzite-imac-postinstall — Post-install configuration for Bazzite on iMac A1419 (Late 2015)
# Usage: sudo ./postinstall.sh [--dry-run]
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}[DRY RUN]${NC} No changes will be made."
    echo ""
fi

do_cmd() {
    local desc="$1"
    shift
    if $DRY_RUN; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} $desc"
        echo "    would run: $*"
    else
        echo -e "  ${GREEN}[EXEC]${NC} $desc"
        "$@"
    fi
}

step_ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
step_skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
step_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root.${NC}" >&2
        exit 1
    fi
}

TOTAL=29
CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)/configs"

echo "============================================"
echo " Bazzite iMac A1419 Post-Install"
echo " 26 steps — $( $DRY_RUN && echo 'DRY RUN' || echo 'LIVE' )"
echo "============================================"
echo ""

if ! $DRY_RUN; then
    require_root
fi

# NOTE: amdgpu.dc=0 is intentionally NOT included. On Tonga GPUs (R9 M395X)
# it causes a ~5-minute boot delay due to 75+ SMU retry loops. The SMU
# "last message was failed" messages in dmesg are cosmetic — the GPU boosts
# correctly with just ppfeaturemask and DPM high.
KARGS=(
    "amdgpu.ppfeaturemask=0xfff7bffd"
    "bluetooth.disable_ertm=1"
    "mitigations=off"
    "intel_pstate=passive"
    "libata.force=1:noncq"
)
CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
for karg in "${KARGS[@]}"; do
    if echo "$CURRENT_KARGS" | grep -q "$karg"; then
        step_skip "Already set: $karg"
    else
        do_cmd "Adding karg: $karg" rpm-ostree kargs --append="$karg"
    fi
done
echo -e "  ${YELLOW}[NOTE]${NC} Reboot required for new kargs to take effect."

SVC_SRC="$CONFIG_DIR/cpu-performance.service"
SVC_DST="/etc/systemd/system/cpu-performance.service"
if [[ -f "$SVC_DST" ]]; then
    step_skip "Service already installed: $SVC_DST"
else
    do_cmd "Copy cpu-performance.service" cp "$SVC_SRC" "$SVC_DST"
    do_cmd "Enable cpu-performance.service" systemctl enable cpu-performance.service
fi

UDEV_CPU_SRC="$CONFIG_DIR/50-cpu-performance.rules"
UDEV_CPU_DST="/etc/udev/rules.d/50-cpu-performance.rules"
if [[ -f "$UDEV_CPU_DST" ]]; then
    step_skip "Udev rule already installed: $UDEV_CPU_DST"
else
    do_cmd "Copy 50-cpu-performance.rules" cp "$UDEV_CPU_SRC" "$UDEV_CPU_DST"
    do_cmd "Reload udev rules" udevadm control --reload-rules
fi

GPU_SRC="$CONFIG_DIR/gpu-dpm-high.service"
GPU_DST="/etc/systemd/system/gpu-dpm-high.service"
if [[ -f "$GPU_DST" ]]; then
    step_skip "Service already installed: $GPU_DST"
else
    do_cmd "Copy gpu-dpm-high.service" cp "$GPU_SRC" "$GPU_DST"
    do_cmd "Enable gpu-dpm-high.service" systemctl enable gpu-dpm-high.service
fi

DRM_SCRIPT="$CONFIG_DIR/wait-for-drm.sh"
WL_SCRIPT="$CONFIG_DIR/wait-for-wayland.sh"
if [[ -f "/usr/local/bin/wait-for-drm.sh" ]]; then
    step_skip "wait-for-drm.sh already installed"
else
    do_cmd "Copy wait-for-drm.sh" cp "$DRM_SCRIPT" /usr/local/bin/wait-for-drm.sh
    do_cmd "Make executable" chmod +x /usr/local/bin/wait-for-drm.sh
fi
if [[ -f "/usr/local/bin/wait-for-wayland.sh" ]]; then
    step_skip "wait-for-wayland.sh already installed"
else
    do_cmd "Copy wait-for-wayland.sh" cp "$WL_SCRIPT" /usr/local/bin/wait-for-wayland.sh
    do_cmd "Make executable" chmod +x /usr/local/bin/wait-for-wayland.sh
fi

PLASMA_SRC="$CONFIG_DIR/plasmalogin-override.conf"
PLASMA_DST="/etc/systemd/system/plasmalogin.service.d/override.conf"
if [[ -f "$PLASMA_DST" ]]; then
    step_skip "Plasma login override already installed"
else
    do_cmd "Create override directory" mkdir -p "$(dirname "$PLASMA_DST")"
    do_cmd "Copy plasmalogin-override.conf" cp "$PLASMA_SRC" "$PLASMA_DST"
    do_cmd "Reload systemd" systemctl daemon-reload
fi

KWIN_SRC="$CONFIG_DIR/kwin-override.conf"
KWIN_DST="/etc/systemd/system/plasma-kwin_wayland.service.d/override.conf"
if [[ -f "$KWIN_DST" ]]; then
    step_skip "KWin override already installed"
else
    do_cmd "Create override directory" mkdir -p "$(dirname "$KWIN_DST")"
    do_cmd "Copy kwin-override.conf" cp "$KWIN_SRC" "$KWIN_DST"
    do_cmd "Reload systemd" systemctl daemon-reload
fi

SDDM_CONF="/etc/sddm.conf.d/00-imac-wallpaper.conf"
if [[ -f "$SDDM_CONF" ]]; then
    step_skip "SDDM wallpaper config already exists"
else
    do_cmd "Create SDDM config directory" mkdir -p /etc/sddm.conf.d
    do_cmd "Write SDDM wallpaper config" bash -c "cat > $SDDM_CONF << 'EOF'
[Theme]
# SDDM will use the system theme; wallpaper is set via plasma-apply-wallpaperimage
# after Wayland is ready via the wait-for-wayland script.
EOF"
fi

EVDI_CONF="/etc/modprobe.d/zz-blacklist-evdi.conf"
if [[ -f "$EVDI_CONF" ]]; then
    step_skip "evdi blacklist already exists"
else
    do_cmd "Write evdi blacklist" bash -c "printf 'blacklist evdi\ninstall evdi /bin/true\n' > $EVDI_CONF"
fi
if systemctl list-unit-files displaylink.service &>/dev/null; then
    do_cmd "Disable displaylink.service" systemctl disable displaylink.service 2>/dev/null || true
else
    step_skip "displaylink.service not present"
fi

for svc in thermald lm_sensors; do
    if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
        do_cmd "Mask $svc" systemctl mask "$svc"
    else
        step_skip "$svc not present or already masked"
    fi
done

ZRAM_CONF="/etc/systemd/zram-generator.conf"
if [[ -f "$ZRAM_CONF" ]]; then
    step_skip "zram-generator.conf already exists"
else
    do_cmd "Write zram-generator.conf" bash -c "cat > $ZRAM_CONF << 'EOF'
[zram0]
zram-size = 8192
compression-algorithm = lz4
EOF"
fi

SYSCTL_SRC="$CONFIG_DIR/sysctl-99-imac.conf"
SYSCTL_DST="/etc/sysctl.d/99-imac.conf"
if [[ -f "$SYSCTL_DST" ]]; then
    step_skip "sysctl config already exists"
else
    do_cmd "Copy sysctl-99-imac.conf" cp "$SYSCTL_SRC" "$SYSCTL_DST"
    do_cmd "Apply sysctl settings" sysctl --system
fi

ENV_SRC="$CONFIG_DIR/gaming-env.sh"
ENV_DST="/etc/profile.d/gaming-env.sh"
if [[ -f "$ENV_DST" ]]; then
    step_skip "gaming-env.sh already installed"
else
    do_cmd "Copy gaming-env.sh" cp "$ENV_SRC" "$ENV_DST"
    do_cmd "Make executable" chmod +x "$ENV_DST"
fi

DXVK_CONF="/etc/dxvk.conf"
if [[ -f "$DXVK_CONF" ]]; then
    step_skip "dxvk.conf already exists"
else
    do_cmd "Write dxvk.conf" bash -c "echo 'dxvk.enableGraphicsPipelineLibrary = False' > $DXVK_CONF"
fi
MANGOHUD_CONF="/etc/mangohud.conf"
if [[ -f "$MANGOHUD_CONF" ]]; then
    step_skip "mangohud.conf already exists"
else
    do_cmd "Write mangohud.conf" bash -c "cat > $MANGOHUD_CONF << 'EOF'
no_display=1
table_columns=20
font_size=18
fps
gpu_name
cpu_name
EOF"
fi
GAMEMODE_CONF="/etc/gamemode.ini"
if [[ -f "$GAMEMODE_CONF" ]]; then
    step_skip "gamemode.ini already exists"
else
    do_cmd "Write gamemode.ini" bash -c "cat > $GAMEMODE_CONF << 'EOF'
[general]
renice=10
desiredgov=performance
softrealtime=auto
reaper_freq=5
defaultgov=powersave
igpu_desiredgov=performance
igpu_power_threshold=0.3
EOF"
fi

# Gamemode is NOT installed — Bazzite bug #173 prevents rpm-ostree from
# layering it. Manual tuning (performance governor, EPB, HWP, sched_autogroup,
# GPU DPM) covers everything gamemode would do.
# See: https://github.com/ublue-os/bazzite-dx/issues/173
# echo -e "\n${GREEN}[STEP 15/${TOTAL}]${NC} Gamemode package (rpm-ostree install)"
# if rpm -q gamemode &>/dev/null; then
#     step_skip "gamemode already installed"
# else
#     do_cmd "Install gamemode" rpm-ostree install gamemode
#     echo -e "  ${YELLOW}[NOTE]${NC} Reboot required to complete gamemode install."
# fi
echo -e "\n${GREEN}[STEP 15/${TOTAL}]${NC} Gamemode package — SKIPPED (see comment above)"

for target in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    if systemctl is-enabled "$target" 2>/dev/null | grep -q "masked"; then
        step_skip "$target already masked"
    else
        do_cmd "Mask $target" systemctl mask "$target"
    fi
done

LOGIND_DIR="/etc/systemd/logind.conf.d"
LOGIND_CONF="$LOGIND_DIR/no-sleep.conf"
if [[ -f "$LOGIND_CONF" ]]; then
    step_skip "logind sleep override already exists"
else
    do_cmd "Create logind.conf.d directory" mkdir -p "$LOGIND_DIR"
    do_cmd "Write no-sleep.conf" bash -c "cat > $LOGIND_CONF << 'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKey=ignore
IdleAction=ignore
IdleActionSec=0
EOF"
    echo -e "  ${YELLOW}[NOTE]${NC} Takes effect on next reboot (systemd-logind reads this at startup)."
fi

IMAC_USER=$(awk -F: '$3>=1000 && $1!="nobody" && $1!="linuxbrew" {print $1; exit}' /etc/passwd 2>/dev/null || echo "")
if [[ -z "$IMAC_USER" ]]; then
    step_skip "No user account found — configure KDE power management manually"
else
    KDE_PWR_CONF="/home/$IMAC_USER/.config/powermanagementprofilesrc"
    if [[ -f "$KDE_PWR_CONF" ]]; then
        step_skip "KDE power management config already exists for $IMAC_USER"
    else
        do_cmd "Create config directory for $IMAC_USER" mkdir -p "/home/$IMAC_USER/.config"
        do_cmd "Write powermanagementprofilesrc" bash -c "cat > $KDE_PWR_CONF << 'EOF'
[AC]
DimDisplay=300000
HandleButSleepButton=0
HandleButHibernateButton=0
SuspendSessionIdle=0
TurnOffDisplayOnBattery=1800000

[Battery]
DimDisplay=120000
HandleButSleepButton=0
HandleButHibernateButton=0
SuspendSessionOnBattery=0
SuspendSessionIdle=0
TurnOffDisplayOnBattery=600000

[LowBattery]
DimDisplay=60000
HandleButSleepButton=0
HandleButHibernateButton=0
SuspendSessionOnBattery=0
SuspendSessionIdle=0
TurnOffDisplayOnBattery=300000
EOF"
        do_cmd "Set ownership to $IMAC_USER" chown "$IMAC_USER:$IMAC_USER" "$KDE_PWR_CONF"
    fi
fi

BT_SRC="$CONFIG_DIR/90-apple-bt-no-suspend.rules"
BT_DST="/etc/udev/rules.d/90-apple-bt-no-suspend.rules"
if [[ -f "$BT_DST" ]]; then
    step_skip "BT udev rule already installed"
else
    do_cmd "Copy 90-apple-bt-no-suspend.rules" cp "$BT_SRC" "$BT_DST"
    do_cmd "Reload udev rules" udevadm control --reload-rules
fi

TONGA_SRC="$CONFIG_DIR/99-amdgpu-tonga"
TONGA_DST="/etc/pm/sleep.d/99-amdgpu-tonga"
if [[ -f "$TONGA_DST" ]]; then
    step_skip "Tonga suspend hook already installed"
else
    do_cmd "Copy 99-amdgpu-tonga" cp "$TONGA_SRC" "$TONGA_DST"
    do_cmd "Make executable" chmod +x "$TONGA_DST"
fi

# Hostname is a user preference. Set it manually: hostnamectl set-hostname <name>

# glmark2 is for verification only. Install it manually if you want to benchmark:
#   rpm-ostree install glmark2

if systemctl is-enabled NetworkManager-wait-online.service &>/dev/null 2>&1; then
    do_cmd "Disable NetworkManager-wait-online" systemctl disable NetworkManager-wait-online.service
else
    step_skip "NetworkManager-wait-online already disabled"
fi

if rpm-ostree initramfs --status 2>/dev/null | grep -q "initramfs.*enabled"; then
    step_skip "hostonly initramfs already enabled"
else
    do_cmd "Enable hostonly initramfs" rpm-ostree initramfs --enable --arg=--hostonly
    echo -e "  ${YELLOW}[NOTE]${NC} Reboot required for initramfs changes to take effect."
fi

# Drive formatting and fstab configuration is left to the user.

# SteamLibrary directory depends on the games drive being mounted first.

HP_SRC="$CONFIG_DIR/fix-headphone.service"
HP_DST="/etc/systemd/system/fix-headphone.service"
if [[ -f "$HP_DST" ]]; then
    step_skip "fix-headphone.service already installed"
else
    do_cmd "Copy fix-headphone.service" cp "$HP_SRC" "$HP_DST"
    do_cmd "Enable fix-headphone.service" systemctl enable fix-headphone.service
fi

FW_SVC_SRC="$CONFIG_DIR/imac-firmware-setup.service"
FW_SVC_DST="/etc/systemd/system/imac-firmware-setup.service"
FW_SCRIPT_SRC="$CONFIG_DIR/imac-firmware-setup.sh"
FW_SCRIPT_DST="/usr/local/bin/imac-firmware-setup.sh"
NVRAM_SRC="$(cd "$(dirname "$0")" && pwd)/firmware/brcmfmac43602-pcie.txt"
NVRAM_DST="/lib/firmware/brcm/brcmfmac43602-pcie.txt"
if [[ -f "$FW_SVC_DST" ]]; then
    step_skip "imac-firmware-setup.service already installed"
else
    do_cmd "Copy imac-firmware-setup.sh" cp "$FW_SCRIPT_SRC" "$FW_SCRIPT_DST"
    do_cmd "Make executable" chmod +x "$FW_SCRIPT_DST"
    do_cmd "Copy imac-firmware-setup.service" cp "$FW_SVC_SRC" "$FW_SVC_DST"
    do_cmd "Enable imac-firmware-setup.service" systemctl enable imac-firmware-setup.service
fi
if [[ -f "$NVRAM_DST" ]]; then
    step_skip "WiFi NVRAM config already installed"
else
    do_cmd "Create firmware directory" mkdir -p /lib/firmware/brcm
    do_cmd "Copy WiFi NVRAM config" cp "$NVRAM_SRC" "$NVRAM_DST"
    do_cmd "Set permissions" chmod 644 "$NVRAM_DST"
fi

# BT firmware (if present in firmware/ directory)
BT_SRC="$(cd "$(dirname "$0")" && pwd)/firmware/BCM20703A1-05ac-8294.hcd"
BT_DST="/lib/firmware/brcm/BCM20703A1-05ac-8294.hcd"
if [[ -f "$BT_SRC" ]]; then
    if [[ -f "$BT_DST" ]]; then
        step_skip "BT firmware already installed"
    else
        do_cmd "Copy BT firmware" cp "$BT_SRC" "$BT_DST"
        do_cmd "Set permissions" chmod 644 "$BT_DST"
    fi
fi

# sensors-imac is for verification only (avoids amdgpu I2C hang).
# Install manually: cp configs/sensors-imac.sh /usr/local/bin/sensors-imac && chmod +x /usr/local/bin/sensors-imac

echo ""
echo "============================================"
echo " Post-install complete!"
if $DRY_RUN; then
    echo " This was a dry run — no changes were made."
    echo " Run without --dry-run to apply changes."
fi
echo "============================================"
echo ""
echo -e "${YELLOW}Recommended next steps:${NC}"
echo "  1. Reboot to apply kernel args and initramfs changes"
echo "  2. Run verify.sh to confirm all settings"
echo "  3. (Optional) Install glmark2 to benchmark GPU: rpm-ostree install glmark2"
echo "  4. (Optional) Install sensors-imac wrapper: cp configs/sensors-imac.sh /usr/local/bin/sensors-imac && chmod +x /usr/local/bin/sensors-imac"
