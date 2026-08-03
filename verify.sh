#!/bin/bash
# bazzite-imac-postinstall — Verification script
# Usage: sudo ./verify.sh [--quick]
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

QUICK=false
if [[ "${1:-}" == "--quick" ]]; then
    QUICK=true
    echo -e "${YELLOW}[QUICK MODE]${NC} Skipping slow checks (initramfs, glmark2, etc.)"
fi

PASSED=0
TOTAL=0

pass() { PASSED=$((PASSED + 1)); echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }

check() {
    local name="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$actual" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name — expected: $expected, actual: $actual"
    fi
}

check_contains() {
    local name="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$actual" | grep -q "$expected"; then
        pass "$name"
    else
        fail "$name — expected to contain: $expected, actual: $actual"
    fi
}

echo "============================================"
echo " Bazzite iMac A1419 — Verification"
echo " $( $QUICK && echo 'QUICK MODE' || echo 'FULL CHECK' )"
echo "============================================"
echo ""

KARGS=$(rpm-ostree kargs 2>/dev/null || echo "UNAVAILABLE")
check_contains "amdgpu.ppfeaturemask" "amdgpu.ppfeaturemask=0xfff7bffd" "$KARGS"
check_contains "bluetooth.disable_ertm" "bluetooth.disable_ertm=1" "$KARGS"
check_contains "mitigations=off" "mitigations=off" "$KARGS"
check_contains "intel_pstate=passive" "intel_pstate=passive" "$KARGS"
check_contains "libata.force=1:noncq" "libata.force=1:noncq" "$KARGS"
# amdgpu.dc=0 MUST NOT be present — it causes a ~5-minute boot delay on Tonga GPUs
TOTAL=$((TOTAL + 1))
if echo "$KARGS" | grep -q "amdgpu.dc=0"; then
    fail "amdgpu.dc=0 is present — must be removed (causes 5-min boot delay on Tonga)"
else
    pass "amdgpu.dc=0 is absent (correct — would cause SMU retry loop)"
fi

if [[ -f /etc/systemd/system/cpu-performance.service ]]; then
    pass "cpu-performance.service file exists"
else
    fail "cpu-performance.service file missing"
fi
SVC_STATUS=$(systemctl is-enabled cpu-performance.service 2>/dev/null || echo "missing")
check "cpu-performance.service enabled" "enabled" "$SVC_STATUS"

if [[ -f /etc/udev/rules.d/50-cpu-performance.rules ]]; then
    pass "50-cpu-performance.rules exists"
else
    fail "50-cpu-performance.rules missing"
fi

if [[ -f /etc/systemd/system/gpu-dpm-high.service ]]; then
    pass "gpu-dpm-high.service file exists"
else
    fail "gpu-dpm-high.service file missing"
fi
GPU_STATUS=$(systemctl is-enabled gpu-dpm-high.service 2>/dev/null || echo "missing")
check "gpu-dpm-high.service enabled" "enabled" "$GPU_STATUS"

if [[ -x /usr/local/bin/wait-for-drm.sh ]]; then
    pass "wait-for-drm.sh exists and executable"
else
    fail "wait-for-drm.sh missing or not executable"
fi
if [[ -x /usr/local/bin/wait-for-wayland.sh ]]; then
    pass "wait-for-wayland.sh exists and executable"
else
    fail "wait-for-wayland.sh missing or not executable"
fi

if [[ -f /etc/systemd/system/plasmalogin.service.d/override.conf ]]; then
    pass "Plasma login override exists"
else
    fail "Plasma login override missing"
fi

if [[ -f /etc/systemd/system/plasma-kwin_wayland.service.d/override.conf ]]; then
    pass "KWin override exists"
else
    fail "KWin override missing"
fi

if [[ -f /etc/sddm.conf.d/00-imac-wallpaper.conf ]]; then
    pass "SDDM wallpaper config exists"
else
    fail "SDDM wallpaper config missing"
fi

if [[ -f /etc/modprobe.d/zz-blacklist-evdi.conf ]]; then
    pass "evdi blacklist exists"
else
    fail "evdi blacklist missing"
fi

for svc in thermald lm_sensors; do
    SVC_STATE=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
    if [[ "$SVC_STATE" == "masked" ]] || [[ "$SVC_STATE" == "not-found" ]]; then
        pass "$svc masked or not present"
    else
        fail "$svc is $SVC_STATE (expected masked)"
    fi
done

if [[ -f /etc/systemd/zram-generator.conf ]]; then
    ZRAM_CONTENT=$(cat /etc/systemd/zram-generator.conf)
    check_contains "zram size 8192" "8192" "$ZRAM_CONTENT"
    check_contains "zram algorithm lz4" "lz4" "$ZRAM_CONTENT"
else
    fail "zram-generator.conf missing"
fi

if [[ -f /etc/sysctl.d/99-imac.conf ]]; then
    pass "99-imac.conf exists"
else
    fail "99-imac.conf missing"
fi
SWAP=$(sysctl -n vm.swappiness 2>/dev/null || echo "UNAVAILABLE")
check "vm.swappiness = 10" "10" "$SWAP"
VFS=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "UNAVAILABLE")
check "vm.vfs_cache_pressure = 50" "50" "$VFS"

if [[ -f /etc/profile.d/gaming-env.sh ]]; then
    ENV_CONTENT=$(cat /etc/profile.d/gaming-env.sh)
    check_contains "RADV_PERFTEST=nosam" "RADV_PERFTEST=nosam" "$ENV_CONTENT"
    check_contains "mesa_glthread=true" "mesa_glthread=true" "$ENV_CONTENT"
    check_contains "DXVK_STATE_CACHE_PATH" "DXVK_STATE_CACHE_PATH" "$ENV_CONTENT"
    check_contains "MESA_GLSL_CACHE_DIR" "MESA_GLSL_CACHE_DIR" "$ENV_CONTENT"
else
    fail "gaming-env.sh missing"
fi

# NOTE: gamemode.ini is NOT verified — gamemode is not installed (Bazzite bug #173
# prevents rpm-ostree from layering it). The config file is written for reference
# but the daemon is absent. Manual tuning covers everything gamemode would do.
for f in /etc/dxvk.conf /etc/mangohud.conf; do
    if [[ -f "$f" ]]; then
        pass "$(basename $f) exists"
    else
        fail "$(basename $f) missing"
    fi
done

for target in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    TARGET_LINK=$(readlink -f /etc/systemd/system/$target 2>/dev/null || echo "not-found")
    if [[ "$TARGET_LINK" == "/dev/null" ]]; then
        pass "$target masked"
    else
        fail "$target not masked (link: $TARGET_LINK)"
    fi
done

if [[ -f /etc/systemd/logind.conf.d/no-sleep.conf ]]; then
    LOGIND_CONTENT=$(cat /etc/systemd/logind.conf.d/no-sleep.conf)
    check_contains "HandleLidSwitch=ignore" "HandleLidSwitch=ignore" "$LOGIND_CONTENT"
    check_contains "HandleSuspendKey=ignore" "HandleSuspendKey=ignore" "$LOGIND_CONTENT"
    check_contains "IdleAction=ignore" "IdleAction=ignore" "$LOGIND_CONTENT"
else
    fail "no-sleep.conf missing"
fi

IMAC_USER=$(awk -F: '$3>=1000 && $1!="nobody" && $1!="linuxbrew" {print $1; exit}' /etc/passwd 2>/dev/null || echo "")
if [[ -n "$IMAC_USER" && -f /home/$IMAC_USER/.config/powermanagementprofilesrc ]]; then
    KDE_PWR=$(cat /home/$IMAC_USER/.config/powermanagementprofilesrc)
    check_contains "AC: HandleButSleepButton=0" "HandleButSleepButton=0" "$KDE_PWR"
    check_contains "AC: SuspendSessionIdle=0" "SuspendSessionIdle=0" "$KDE_PWR"
    check_contains "AC: DimDisplay=300000" "DimDisplay=300000" "$KDE_PWR"
else
    fail "powermanagementprofilesrc missing"
fi

if [[ -f /etc/udev/rules.d/90-apple-bt-no-suspend.rules ]]; then
    pass "90-apple-bt-no-suspend.rules exists"
else
    fail "90-apple-bt-no-suspend.rules missing"
fi

if [[ -x /etc/pm/sleep.d/99-amdgpu-tonga ]]; then
    pass "99-amdgpu-tonga exists and executable"
else
    fail "99-amdgpu-tonga missing or not executable"
fi

# Hostname is a user preference, not a hardware check — skip verification
HOSTNAME=$(hostname 2>/dev/null || echo "UNAVAILABLE")
pass "hostname = $HOSTNAME (detected)"

if $QUICK; then
    skip "Skipped in quick mode"
else
    if rpm -q glmark2 &>/dev/null; then
        pass "glmark2 installed"
    else
        fail "glmark2 not installed"
    fi
fi

NM_STATUS=$(systemctl is-enabled NetworkManager-wait-online.service 2>/dev/null || echo "not-found")
if [[ "$NM_STATUS" == "disabled" ]] || [[ "$NM_STATUS" == "not-found" ]]; then
    pass "NetworkManager-wait-online disabled"
else
    fail "NetworkManager-wait-online is $NM_STATUS (expected disabled)"
fi

if $QUICK; then
    skip "Skipped in quick mode"
else
    INITRAMFS_STATUS=$(rpm-ostree initramfs --status 2>/dev/null || echo "UNAVAILABLE")
    if echo "$INITRAMFS_STATUS" | grep -q "initramfs.*enabled"; then
        pass "hostonly initramfs enabled"
    else
        fail "hostonly initramfs not enabled — run: rpm-ostree initramfs --enable --arg=--hostonly"
    fi
fi

if [[ -f /etc/systemd/system/fix-headphone.service ]]; then
    pass "fix-headphone.service file exists"
else
    fail "fix-headphone.service file missing"
fi
HP_STATUS=$(systemctl is-enabled fix-headphone.service 2>/dev/null || echo "missing")
check "fix-headphone.service enabled" "enabled" "$HP_STATUS"

if [[ -f /etc/systemd/system/imac-firmware-setup.service ]]; then
    pass "imac-firmware-setup.service file exists"
else
    fail "imac-firmware-setup.service file missing"
fi
FW_STATUS=$(systemctl is-enabled imac-firmware-setup.service 2>/dev/null || echo "missing")
check "imac-firmware-setup.service enabled" "enabled" "$FW_STATUS"
if [[ -x /usr/local/bin/imac-firmware-setup.sh ]]; then
    pass "imac-firmware-setup.sh exists and executable"
else
    fail "imac-firmware-setup.sh missing or not executable"
fi

if [[ -x /usr/local/bin/sensors-imac ]]; then
    pass "sensors-imac exists and executable"
else
    fail "sensors-imac missing or not executable"
fi

if [[ -f /lib/firmware/brcm/BCM20703A1-05ac-8294.hcd ]]; then
    pass "BCM20703A1-05ac-8294.hcd exists"
else
    fail "BCM20703A1-05ac-8294.hcd missing"
fi
BT_SYMLINK=$(readlink -f /lib/firmware/brcm/BCM-05ac-8294.hcd 2>/dev/null || echo "missing")
if [[ "$BT_SYMLINK" == "/lib/firmware/brcm/BCM20703A1-05ac-8294.hcd" ]]; then
    pass "BCM-05ac-8294.hcd symlink correct"
else
    fail "BCM-05ac-8294.hcd symlink missing or wrong target"
fi

FW_BIN=$(readlink -f "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-iMac17,1.bin" 2>/dev/null || echo "missing")
if [[ "$FW_BIN" == "/lib/firmware/brcm/brcmfmac43602-pcie.bin" ]]; then
    pass "WiFi firmware symlink correct"
else
    fail "WiFi firmware symlink missing or wrong target"
fi
# NOTE: No clm_blob symlink check — ap.bin is NOT a CLM blob.
# Symlinking it as clm_blob causes "clmload failed (-52)" and crashes the dongle.
# The driver works without a CLM blob (limited channels, harmless warnings).
if [[ -f /lib/firmware/brcm/brcmfmac43602-pcie.txt ]]; then
    pass "WiFi NVRAM config exists"
else
    fail "WiFi NVRAM config missing"
fi

echo ""
echo "============================================"
echo -e " Results: ${GREEN}${PASSED}${NC}/${TOTAL} passed"
if [[ $PASSED -eq $TOTAL ]]; then
    echo -e " ${GREEN}All checks passed!${NC}"
else
    echo -e " ${RED}$((TOTAL - PASSED)) check(s) failed.${NC}"
fi
echo "============================================"
