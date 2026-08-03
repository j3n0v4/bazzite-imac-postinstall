# Bazzite iMac A1419 (Late 2015) — Post-Install Guide

> **TL;DR:** I bought a 2015 iMac at a thrift store, upgraded it, and installed Bazzite 44 for retro gaming. This repo has the post-install config I wrote to fix boot hangs, GPU black screens, CPU throttling, and Bluetooth. Run `postinstall.sh` after a fresh Bazzite install, then `verify.sh` to confirm everything stuck.
>
> **Tested on Bazzite 44.** May not work on newer versions — check before applying.

## Why This Exists

I found a Late 2015 27" iMac (A1419) at a thrift store, upgraded it (i7-6700K, 32GB RAM, 512GB NVMe, R9 M395X, 6TB HDD), and replaced macOS with [Bazzite](https://bazzite.gg/). The hardware works with Linux, but several defaults need tweaking for this specific machine.

This repo is my documented, scripted post-install. Every optimization was tested against real benchmarks and boot-time measurements. I'm sharing it so anyone else putting Bazzite on a 2015 iMac doesn't have to rediscover the same fixes.

**Official Bazzite docs** are the authoritative source for general setup. This repo only covers iMac-specific overrides. See:
- [Bazzite Installation Guide](https://docs.bazzite.gg/Install/)
- [Bazzite FAQ / Troubleshooting](https://docs.bazzite.gg/General/FAQ/)

## Test Hardware

| Component | Spec |
|-----------|------|
| **Model** | iMac A1419 (Late 2015, iMac17,1) |
| **CPU** | Intel Core i7-6700K (Skylake, 4C/8T @ 4.0 GHz) |
| **GPU** | AMD Radeon R9 M395X (Tonga, GCN 3.0, 4 GB GDDR5) |
| **RAM** | 32 GB DDR3L @ 1867 MHz |
| **Boot Drive** | Kingston SKC3000S512G (512 GB NVMe, PCIe 3.0 x2) |
| **Storage** | WD Blue 6 TB HDD (SATA, 5400 RPM, 128 MB cache, SMR) |
| **Display** | 27" 5120×2880 internal (eDP) |
| **WiFi** | Broadcom BCM43602 (802.11ac) |
| **Bluetooth** | Broadcom BCM20703A1 (USB 05ac:8294) |
|| **Audio** | Realtek ALC887 (internal speakers + headphone jack) |
|| **Webcam** | Apple FaceTime HD Camera (05ac:8511, USB 2.0, UVC) |
|| **SD Card** | Broadcom BCM57785 SDXC/MMC Card Reader (PCIe) |

## Display Note

The native panel is 5120×2880 (5K), but Linux maxes out at 3840×2160 (4K). macOS drives 5K via MST (Multi-Stream Transport), splitting the signal across two DisplayPort streams. The Linux AMDGPU driver doesn't support MST on internal eDP panels, so it falls back to single-stream DP 1.2, which caps at 4K.

## Boot Time

I spent significant time optimizing boot on this hardware. The Z170 firmware enumeration is the bottleneck — it's hardware-bound and can't be reduced.

| Phase | Time | Notes |
|-------|------|-------|
| UEFI (Z170 POST) | ~10s | Hardware-bound — Z170 firmware enumeration |
| Kernel init | ~0.7s | hostonly initramfs |
| initramfs | ~32s | AMDGPU module load for Tonga (hardware-bound) |
| AMDGPU init | ~4s | Tonga DRM init |
| KDE Plasma | ~7s | wait-for-drm prevents retries |
| Userspace | ~22s | Services, desktop |
| **Total** | **~57s** | On my hardware — yours will vary |

**Time to login screen:** ~54s
**Time to usable desktop:** ~57s

On my hardware — yours will vary.

## Quick Start

```bash
# 1. Clone and inspect
git clone https://github.com/j3n0v4/bazzite-imac-postinstall.git
cd bazzite-imac-postinstall

# 2. Apply (dry run first)
sudo ./postinstall.sh --dry-run
sudo ./postinstall.sh

# 3. Reboot and verify
sudo reboot
sudo ./verify.sh
```

## Documentation

| File | What It Covers |
|------|----------------|
| [INSTALL.md](./INSTALL.md) | Step-by-step from a fresh Bazzite install |

## Works Out of the Box

These components need zero configuration on Bazzite:

- **Fan** — Works out of the box
- **Display** — Works out of the box
- **Webcam** — Apple FaceTime HD Camera (05ac:8511), works out of the box
- **SD Card** — Broadcom BCM57785 SDXC/MMC reader, works out of the box

## What Works

- **CPU** — `performance` governor on all 8 cores, EPB=0, HWP=performance
- **GPU** — DPM high, 3D_FULL_SCREEN profile, ppfeaturemask active
- **Bluetooth** — BCM20703A1 working, firmware included in repo
- **Audio** — Speakers and mic working, headphone fix service
- **Storage** — NVMe (PCIe 3.0 x2, ~2.5 GB/s) and SATA (6 TB HDD)
- **Gaming Env** — All vars set (RADV_PERFTEST, mesa_glthread, DXVK/MESA caches)

## Hardware Status

| Component | Status | Notes |
|-----------|--------|-------|
| CPU | ✅ | Performance governor |
| GPU | ✅ | DPM high |
| WiFi | ⚠️ | Needs NVRAM config + firmware symlinks |
| Bluetooth | ⚠️ | Needs firmware from `firmware/` |
| Audio — Speakers | ✅ | |
| Audio — Headphones | ⚠️ | Needs fix-headphone service |
| Audio — Mic | ✅ | |
| Fan | ✅ | SMC auto |
| Display | ⚠️ | Max 3840×2160 (5K needs MST, unsupported on eDP) |
| Webcam | ✅ | |
| SD Card | ✅ | |
| Sleep | ❌ | Disabled — Tonga wake issues |

## What the Script Handles

These issues are resolved by `postinstall.sh` — no manual intervention needed:

- **WiFi (BCM43602):** NVRAM config and firmware symlinks provisioned at boot by `imac-firmware-setup.service`
- **Bluetooth (BCM20703A1):** Firmware included in `firmware/`, installed at boot
- **Headphone jack (CS4206):** Unmuted and configured at boot by `fix-headphone.service`
- **CPU governor:** Forced to `performance` at boot
- **GPU DPM:** Forced to `high` at boot
- **Sleep:** Fully disabled (Tonga GPU has permanent black screen on wake)

## Known Limitations

- **Sleep** — Intentionally disabled. The Tonga GPU (R9 M395X) has known wake-from-sleep issues that cause a permanent black screen. Sleep/suspend/hibernate targets are masked at three layers (systemd, logind, KDE). The display still dims and turns off after 30 min.

## Configuration Overview

The `postinstall.sh` script handles all of these:

- Kernel arguments (5 args)
- CPU governor service + udev rule
- GPU DPM high service
- Boot scripts (wait-for-drm, wait-for-wayland)
- Plasma login + KWin overrides
- evdi blacklist
- thermald + lm_sensors masking
- zram (8 GB, lz4)
- sysctl tuning
- Gaming environment variables
- DXVK, MangoHud configs
- Sleep disabled (systemd + logind + KDE)
- Bluetooth no-autosuspend udev rule
- Tonga suspend hook
- NetworkManager-wait-online disabled
- hostonly initramfs
- Headphone audio fix
- Firmware setup service

## Verification

Optional tools for checking your setup:

```bash
# GPU benchmark (requires install)
rpm-ostree install glmark2
glmark2-wayland

# Temperature monitoring (avoids amdgpu I2C hang)
cp configs/sensors-imac.sh /usr/local/bin/sensors-imac
chmod +x /usr/local/bin/sensors-imac
sensors-imac
```

Run `verify.sh` to check all postinstall configuration:

```bash
sudo ./verify.sh          # Full check
sudo ./verify.sh --quick  # Skip slow checks (initramfs, glmark2)
```


