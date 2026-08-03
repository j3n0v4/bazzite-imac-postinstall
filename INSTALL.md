# Install — iMac A1419 on Bazzite

From a fresh Bazzite install to fully configured.

## Requirements

- Bazzite 44 (KDE Plasma) installed. Tested on this version — may not work on newer releases.
- Internet connection (Ethernet recommended)

## Steps

```bash
sudo rpm-ostree install git
git clone https://github.com/j3n0v4/bazzite-imac-postinstall.git
cd bazzite-imac-postinstall
sudo ./postinstall.sh --dry-run   # review what will change
sudo ./postinstall.sh              # apply
sudo reboot
sudo ./verify.sh
```

## Common Problems

| Problem | Fix |
|---------|-----|
| Black screen on boot | Check: `journalctl -u plasmalogin.service \| grep wait` |
| KWin crashes | Auto-restarts via override. Normal on Tonga. |
| WiFi not connecting | `dmesg \| grep brcmfmac` — check NVRAM config |
| Bluetooth empty | `bluetoothctl power on` — needs power-on after fresh boot |
| No headphone sound | `systemctl restart fix-headphone.service` |
| `sensors` hangs | Use `sensors-imac` instead |