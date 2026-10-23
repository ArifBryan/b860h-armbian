#!/bin/bash
# One-shot setup for the ZTE B860H.
#
#   sudo bash b860h-setup.sh                 patch this system: LEDs, power button, upgrade guard
#   sudo bash b860h-setup.sh --emmc          patch, then install to the eMMC and verify it (ERASES the eMMC)
#
# Options for --emmc:
#   --flash-uboot   write uboot/uboot_HG680P.bin to the eMMC if it does not already hold it
#   --yes           do not ask for the YES confirmation before erasing the eMMC
#   --allow-stale   install even if this git clone is behind origin (by default it refuses, see install-b860h.sh)
#
# Run --emmc from the SD card. It uses scripts/install-aml.sh, a copy of the stock installer,
# so it does not depend on what a given Armbian image release ships.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
S=$REPO/scripts
DO_EMMC=0
FLASH_UBOOT=0
ASSUME_YES=0

die() { echo "ERROR: $*" >&2; exit 1; }

for a in "$@"; do
	case "$a" in
		--emmc) DO_EMMC=1 ;;
		--flash-uboot) FLASH_UBOOT=1 ;;
		--yes) ASSUME_YES=1 ;;
		--allow-stale) export B860H_ALLOW_STALE=1 ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) sed -n '2,13p' "$0"; exit 1 ;;
	esac
done

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0 $*"
[ "$FLASH_UBOOT" -eq 0 ] || [ "$DO_EMMC" -eq 1 ] || die "--flash-uboot only makes sense with --emmc"

if [ "$DO_EMMC" -eq 1 ]; then
	# Check everything that can fail BEFORE patching or erasing anything.
	[ -f "$S/install-aml.sh" ] || die "$S/install-aml.sh is missing"
	EMMC=""
	for b in /sys/block/mmcblk[0-9]; do
		n=$(basename "$b")
		[ -b "/dev/${n}boot0" ] && EMMC=$n
	done
	[ -n "$EMMC" ] || die "no eMMC found"
	case "$(findmnt -no SOURCE /)" in
		/dev/"$EMMC"p*) die "you are running from the eMMC; boot the SD card for --emmc" ;;
	esac
fi

echo "######## 1/4 Patching this system"
bash "$S/install-b860h.sh"

[ "$DO_EMMC" -eq 1 ] || { echo; echo "Done. Reboot to activate the LEDs and power button, or run again with --emmc to install to the eMMC."; exit 0; }

echo
echo "######## 2/4 Checking the eMMC bootloader"
if ! bash "$S/check-emmc-uboot.sh"; then
	[ "$FLASH_UBOOT" -eq 1 ] || die "eMMC bootloader mismatch. Re-run with --flash-uboot to write uboot_HG680P.bin to /dev/$EMMC"
	echo "Writing uboot_HG680P.bin to /dev/$EMMC"
	bash "$S/write-uboot.sh" "/dev/$EMMC" --yes
	bash "$S/check-emmc-uboot.sh" || die "bootloader still does not match after writing it"
fi

echo
echo "######## 3/4 Installing to the eMMC (scripts/install-aml.sh, a copy of the stock installer)"
lsblk -o NAME,SIZE,FSTYPE,LABEL "/dev/$EMMC"
if [ "$ASSUME_YES" -ne 1 ]; then
	read -r -p "This ERASES /dev/$EMMC and copies the running SD system to it. Type YES: " ans
	[ "$ans" = "YES" ] || die "aborted (nothing was erased)"
fi
sh "$S/install-aml.sh"

echo
echo "######## 4/4 Verifying the eMMC boot partition"
bash "$S/fix-emmc-boot.sh"

echo
echo "All done. Next, in this order:"
echo "  1. sudo reboot            (keep the SD card IN; wait until the SD system is fully back up)"
echo "  2. sudo poweroff          then remove the SD card and power on"
echo "If you remove the SD card right now, the eMMC will not start: the box has to run the SD card's"
echo "aml_autoscript once first. The first eMMC boot afterwards can take a few minutes."
