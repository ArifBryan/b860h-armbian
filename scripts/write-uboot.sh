#!/bin/bash
# Write the HG680P U-Boot image into the bootloader area of the box's eMMC (or a disk image file).
# Only needed when scripts/check-emmc-uboot.sh reports a mismatch. NOT for SD cards: those only need
# u-boot.ext (a renamed copy of u-boot-s905x-s912) on the FAT partition, and the image's first partition
# may start inside the 4 MB this writes.
#
#   sudo ./write-uboot.sh /dev/mmcblkN [uboot.bin]  (whole eMMC disk, not a partition)
#   ./write-uboot.sh image.img [uboot.bin]          (test on a plain file)
#
# Only bytes 0-441 (boot code) and sectors 1-8191 are written; the partition table
# (bytes 446-511) and everything from 4 MB on are left untouched.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ASSUME_YES=0
ARGS=()
for a in "$@"; do
	case "$a" in
		-y|--yes) ASSUME_YES=1 ;;
		*) ARGS+=("$a") ;;
	esac
done
TARGET=${ARGS[0]:-}
BIN=${ARGS[1]:-$HERE/../uboot/uboot_HG680P.bin}

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
	if [ "$ASSUME_YES" -ne 1 ]; then
		read -r -p "Write the bootloader to $TARGET? Type YES: " ans
		[ "$ans" = "YES" ] || { echo aborted; exit 1; }
	fi
elif [ -f "$TARGET" ]; then
	[ "$(stat -c %s "$TARGET")" -ge 4194304 ] || { echo "$TARGET is smaller than 4 MiB" >&2; exit 1; }
else
	echo "$TARGET is neither a block device nor a file" >&2; exit 1
fi

dd if="$BIN" of="$TARGET" bs=1 count=442 conv=notrunc,fsync status=none
dd if="$BIN" of="$TARGET" bs=512 skip=1 seek=1 count=8191 conv=notrunc,fsync status=none
sync
echo "Bootloader written to $TARGET."
