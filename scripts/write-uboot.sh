#!/bin/bash
# Write the HG680P U-Boot image into the bootloader area of an SD card (or a disk image file).
# The B860H only boots Armbian with this bootloader. Run it after flashing the Armbian image.
#
#   sudo ./write-uboot.sh /dev/sdX [uboot.bin]      (whole disk, not a partition)
#   ./write-uboot.sh image.img [uboot.bin]          (test on a plain file)
#
# Only bytes 0-441 (boot code) and sectors 1-8191 are written; the partition table
# (bytes 446-511) and everything from 4 MB on are left untouched.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:-}
BIN=${2:-$HERE/../uboot/uboot_HG680P.bin}

[ -n "$TARGET" ] || { sed -n '2,10p' "$0"; exit 1; }
[ -f "$BIN" ] || { echo "missing $BIN" >&2; exit 1; }
[ "$(stat -c %s "$BIN")" -eq 4194304 ] || { echo "$BIN is not a 4 MiB image" >&2; exit 1; }

if [ -b "$TARGET" ]; then
	[ "$(lsblk -dno TYPE "$TARGET")" = "disk" ] || { echo "$TARGET is not a whole disk (use /dev/sdX, not /dev/sdX1)" >&2; exit 1; }
	if lsblk -no MOUNTPOINT "$TARGET" | grep -qx '/\|/boot\|/home'; then
		echo "$TARGET holds a system mount; refusing." >&2; exit 1
	fi
	SIZE=$(lsblk -bdno SIZE "$TARGET")
	echo "Target: $TARGET  $(lsblk -dno SIZE,MODEL "$TARGET" | xargs)"
	if [ "$SIZE" -gt $((256 * 1024 * 1024 * 1024)) ]; then
		echo "That disk is larger than 256 GiB; it is probably not your SD card." >&2; exit 1
	fi
	read -r -p "Write the bootloader to $TARGET? Type YES: " ans
	[ "$ans" = "YES" ] || { echo aborted; exit 1; }
elif [ -f "$TARGET" ]; then
	[ "$(stat -c %s "$TARGET")" -ge 4194304 ] || { echo "$TARGET is smaller than 4 MiB" >&2; exit 1; }
else
	echo "$TARGET is neither a block device nor a file" >&2; exit 1
fi

dd if="$BIN" of="$TARGET" bs=1 count=442 conv=notrunc,fsync status=none
dd if="$BIN" of="$TARGET" bs=512 skip=1 seek=1 count=8191 conv=notrunc,fsync status=none
sync
echo "Bootloader written to $TARGET."
