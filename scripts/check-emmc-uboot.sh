#!/bin/bash
# Read-only check: does the eMMC already hold the HG680P bootloader?
# Run this on the SD system BEFORE the stock /root/install-aml.sh, which only backs up and
# restores whatever bootloader is on the eMMC and never writes one itself.
#
#   sudo ./check-emmc-uboot.sh
#
# If it reports a mismatch, write the bootloader first:
#   sudo ./write-uboot.sh /dev/mmcblkN        (N as printed below)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN=$HERE/../uboot/uboot_HG680P.bin

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }

# The eMMC is the mmcblk device with hardware boot partitions; its number depends on the dtb.
EMMC=""
for b in /sys/block/mmcblk[0-9]; do
	n=$(basename "$b")
	[ -b "/dev/${n}boot0" ] && EMMC=$n
done
[ -n "$EMMC" ] || { echo "No eMMC found." >&2; exit 1; }

head_md5() { dd if="$1" bs=512 skip=1 count=8191 2>/dev/null | md5sum | cut -d' ' -f1; }
WANT=$(head_md5 "$BIN")
HAVE=$(head_md5 "/dev/$EMMC")

echo "eMMC device : /dev/$EMMC"
echo "expected    : $WANT"
echo "found       : $HAVE"
if [ "$WANT" = "$HAVE" ]; then
	echo "OK: the eMMC has the HG680P bootloader. You can run /root/install-aml.sh."
else
	echo "MISMATCH: the eMMC does not hold uboot_HG680P.bin; Armbian would not boot from it."
	echo "Fix: sudo $HERE/write-uboot.sh /dev/$EMMC"
	exit 2
fi
