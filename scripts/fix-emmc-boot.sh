#!/bin/bash
# Run on the SD system AFTER scripts/install-aml.sh. Then reboot once with the SD card still in (the box
# runs the card's aml_autoscript once), and only then power off and remove the card.
# It checks that the eMMC will boot, and pins root= to the eMMC's UUID (the stock installer
# writes root=LABEL=ROOT_EMMC, which depends on label lookup in the initramfs).
#
#   sudo ./fix-emmc-boot.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }

EMMC=""
for b in /sys/block/mmcblk[0-9]; do
	n=$(basename "$b")
	[ -b "/dev/${n}boot0" ] && EMMC=$n
done
[ -n "$EMMC" ] || { echo "No eMMC found." >&2; exit 1; }
case "$(findmnt -no SOURCE /)" in
	/dev/"$EMMC"p*) echo "You are running from the eMMC; run this from the SD card." >&2; exit 1 ;;
esac

P1=/dev/${EMMC}p1
P2=/dev/${EMMC}p2
[ "$(blkid -s LABEL -o value "$P1")" = "BOOT_EMMC" ] || { echo "$P1 is not BOOT_EMMC; was install-aml.sh run?" >&2; exit 1; }
[ "$(blkid -s LABEL -o value "$P2")" = "ROOT_EMMC" ] || { echo "$P2 is not ROOT_EMMC; was install-aml.sh run?" >&2; exit 1; }
ROOT_UUID=$(blkid -s UUID -o value "$P2")

MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
mount "$P1" "$MNT"

fail=0
need() { [ -e "$MNT/$1" ] || { echo "MISSING on eMMC boot partition: $1" >&2; fail=1; }; }
need emmc_autoscript
need u-boot.emmc
need extlinux/extlinux.conf
need Image
need uInitrd

for f in aml_autoscript s905_autoscript; do
	if [ -e "$MNT/$f" ]; then
		echo "Removing $f (it breaks eMMC boot)"
		rm -f "$MNT/$f"
	fi
done

# emmc_autoscript runs `go 0x1000000` on u-boot.emmc, so it must be a raw ARM64 U-Boot (the 646 KB
# file). install-aml.sh makes it by renaming the SD card's u-boot.ext; if that was the 4 MB HG680P
# image (prepare-sd.bat default), the eMMC would not boot. Always install the right file.
GOOD=$(dirname "$0")/../uboot/u-boot.ext
if [ -f "$GOOD" ]; then
	if ! cmp -s "$GOOD" "$MNT/u-boot.emmc"; then
		echo "Replacing u-boot.emmc ($(stat -c %s "$MNT/u-boot.emmc" 2>/dev/null || echo missing) bytes) with uboot/u-boot.ext ($(stat -c %s "$GOOD") bytes)"
		cp -f "$GOOD" "$MNT/u-boot.emmc"
	fi
else
	echo "WARNING: $GOOD not found; u-boot.emmc left as the installer made it" >&2
fi

CONF=$MNT/extlinux/extlinux.conf
if [ -f "$CONF" ]; then
	sed -i "s#root=[^ ]*#root=UUID=$ROOT_UUID#" "$CONF"
	FDT=$(sed -n 's/^[[:space:]]*[Ff][Dd][Tt][[:space:]]\+\([^[:space:]]*\).*/\1/p' "$CONF" | head -n 1)
	[ -n "$FDT" ] && [ ! -f "$MNT$FDT" ] && { echo "MISSING dtb referenced by extlinux: $FDT" >&2; fail=1; }
	grep -niE '^[[:space:]]*fdt[[:space:]]|root=' "$CONF"
fi
sync

if [ "$fail" -ne 0 ]; then
	echo "NOT READY: fix the items above before removing the SD card." >&2
	exit 1
fi
echo "OK: eMMC boot partition looks good (root=UUID=$ROOT_UUID)."
echo "Now reboot ONCE with the SD card still in and wait until it is back up; only then power off and remove the card."
