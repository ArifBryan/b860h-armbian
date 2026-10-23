#!/bin/bash
# Patch a fresh Armbian install for the ZTE B860H:
#   - LEDs (green power, red activity) and the power button, in the kernel, via a DT overlay
#   - /usr/local/sbin/b860h-dtb-guard, hooked into apt, so upgrades can't break boot
# Safe to run more than once. Run as root on the box (SD card or eMMC).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
mountpoint -q /boot || { echo "/boot is not a separate mounted partition; this box layout is not supported." >&2; exit 1; }
[ -f /boot/extlinux/extlinux.conf ] || { echo "No /boot/extlinux/extlinux.conf found." >&2; exit 1; }

echo "== Installing device-tree-compiler"
apt-get update -qq || true
apt-get install -y device-tree-compiler

echo "== Installing overlay and guard"
install -D -m 644 "$REPO/dts/b860h-extras.dts" /usr/local/share/b860h/b860h-extras.dts
install -D -m 755 "$HERE/b860h-dtb-guard" /usr/local/sbin/b860h-dtb-guard
printf 'DPkg::Post-Invoke { "/usr/local/sbin/b860h-dtb-guard"; };\n' > /etc/apt/apt.conf.d/99-b860h

echo "== Disabling the old userspace power-button script, if present"
for svc in powerButton.service; do
	if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
		systemctl disable --now "$svc" || true
	fi
done

echo "== Building /boot/b860h.dtb"
/usr/local/sbin/b860h-dtb-guard

echo
grep -niE '^[[:space:]]*fdt[[:space:]]' /boot/extlinux/extlinux.conf || true
if [ -f /boot/b860h.dtb ] && grep -qiE '^[[:space:]]*fdt[[:space:]]+/b860h\.dtb' /boot/extlinux/extlinux.conf; then
	ls -l /boot/b860h.dtb
	echo "OK. Reboot to activate the LEDs and power button."
else
	echo "WARNING: the overlay build failed; extlinux is using the stock dtb (boots fine, no LEDs/button)." >&2
	exit 2
fi
