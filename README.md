# Armbian on the ZTE B860H (Amlogic S905X)

Boot Armbian from SD, then install it on the eMMC so that **package upgrades don't break boot**,
with the **LEDs and the power button handled by the kernel** (no userspace scripts).

## What goes wrong on a stock install, and what this repo does about it

| Problem | Fix here |
|---|---|
| Armbian only boots on this box with the **HG680P** U-Boot image in the first 4 MB of the SD card / eMMC | `uboot/uboot_HG680P.bin` plus `scripts/write-uboot.*` and `scripts/check-emmc-uboot.sh` |
| `apt upgrade` re-adds `aml_autoscript` / `s905_autoscript` to the eMMC `/boot`; they chain to `u-boot.ext`, which the eMMC install renamed to `u-boot.emmc`, so the eMMC no longer boots | `scripts/b860h-dtb-guard`, run by apt after every upgrade, removes them again (eMMC only) |
| The old hand-edited full device tree dump does not work with newer kernels (6.18 official) | `dts/b860h-extras.dts` is a small overlay. The guard applies it to the kernel's own `meson-gxl-s905x-p212.dtb` after every upgrade, so the dtb always matches the kernel. If the build ever fails it falls back to the stock dtb |
| LEDs / power button were driven by a userspace loop | In the overlay: `gpio-leds` (green = power, red = CPU `activity`) and `gpio-keys-polled` (power button, polled because the GXL GPIO irq controller cannot do both-edge interrupts) |

## Which image

Use the community build for the **`aml-s9xx-box`** board (generic Amlogic S9xx TV box):

**Debian 13 (trixie), `current` kernel 6.18, minimal**, from <https://www.armbian.com/aml-s9xx-box/>

```
https://dl.armbian.com/aml-s9xx-box/Trixie_current_minimal
(= Armbian_community_..._Aml-s9xx-box_trixie_current_6.18.57_minimal.img.xz)
```

Notes:
- Stay on **`current`**, not `edge` (7.x): 6.18 is what this repo is tested with.
- *Server* instead of *minimal* also works; *Xfce* is a waste on this box.
- The download page has a `.sha` file next to each image: verify it.
- The image ships `/root/install-aml.sh`, the stock eMMC installer used below.
- Build date and version change often; take the newest `Trixie_current_*` build.

## 1. Make the bootable SD card (Windows)

1. Flash the `.img.xz` to the SD card with **Armbian Imager** or balenaEtcher.
   (Use a good 8 GB+ card, and a card reader. Do not use a USB-SD adapter that hides the raw disk.)
2. Windows now shows a small **BOOT** (FAT) drive. Open `extlinux\extlinux.conf` on it and make sure
   exactly one `FDT` line is active, the S905X one:
   ```
   FDT /dtb/amlogic/meson-gxl-s905x-p212.dtb
   ```
   (comment out the others with `#`). This is only for the first boot; the repo's guard takes over later.
3. Write the HG680P bootloader into the SD card's boot area. In an **elevated PowerShell**:
   ```powershell
   Get-Disk                       # find the SD card's number (USB/SD bus, right size)
   .\scripts\write-uboot.ps1 -DiskNumber 3
   ```
   If Windows denies the write: `Set-Disk -Number 3 -IsOffline $true`, run the script, then
   `Set-Disk -Number 3 -IsOffline $false`.
   On Linux instead: `sudo ./scripts/write-uboot.sh /dev/sdX` (whole disk, not a partition).
   Both scripts write only boot-code bytes 0-441 and sectors 1-8191; the partition table and the
   data are untouched. Verified on a disk image file: the shell and PowerShell versions produce
   byte-identical results.
4. Put the SD card in the box, power on. First boot takes a minute or two (partition resize, first-run
   wizard). Watch HDMI or find the IP in your router, and `ssh root@<ip>` (default password `1234`,
   you are forced to change it and create a user).

If the box ignores the SD card (a unit that still has the stock Android bootloader): power off, hold the
reset button inside the AV port with a toothpick, then power on.

## 2. Patch the SD system (LEDs, power button, upgrade guard)

On the box, as root:

```bash
apt update && apt install -y git
git clone <this repo> b860h-armbian && cd b860h-armbian
sudo ./scripts/install-b860h.sh
sudo reboot
```

After the reboot: the green LED is on, the red LED flickers with CPU load, and a short press on the power
button powers the box off. `grep ^FDT /boot/extlinux/extlinux.conf` should say `FDT /b860h.dtb`.

## 3. Install to the eMMC

Boot from the SD card, with the patch from step 2 installed, then:

```bash
cd b860h-armbian

# 1. Does the eMMC already hold the HG680P bootloader? (read-only check)
sudo ./scripts/check-emmc-uboot.sh
#    On MISMATCH, write it first (this replaces the eMMC bootloader; the SD card stays your fallback):
#    sudo ./scripts/write-uboot.sh /dev/mmcblk1      # use the device the check script prints

# 2. The stock installer: it ERASES the eMMC and copies the running SD system to it
sudo /root/install-aml.sh

# 3. Make the result bulletproof (root=UUID, no SD boot scripts, files present)
sudo ./scripts/fix-emmc-boot.sh
```

Wait for `OK: eMMC boot partition looks good`, then:

```bash
sudo poweroff
```

Remove the SD card and power on. Check:

```bash
findmnt -no SOURCE /          # /dev/mmcblk?p2 on the eMMC
ls /sys/class/leds            # green:power  red:status
ls /boot | grep autoscript    # only emmc_autoscript
```

## 4. Upgrading safely

`sudo apt update && sudo apt full-upgrade` is now safe: after every run, the guard rebuilds `/boot/b860h.dtb`
from the new kernel's stock dtb and removes the SD-card boot scripts. Before a **kernel** upgrade you can take
a snapshot to restore from the SD card if anything goes wrong:

```bash
sudo tar czf /root/boot-$(date +%F).tgz -C /boot .
```

To check an upgrade without rebooting: `ls /boot | grep autoscript` (only `emmc_autoscript`),
`grep -E '^FDT|root=' /boot/extlinux/extlinux.conf` (`FDT /b860h.dtb`, `root=UUID=...`), and
`ls /lib/modules` (a folder for the new kernel).

## Notes and gotchas

- **Device names change with the dtb**: with the old custom dtb the eMMC was `mmcblk2`, with the stock-based
  dtb it is `mmcblk1`. The scripts find the eMMC by its `boot0` hardware partition instead of by number.
  Always use UUID/LABEL in your own commands.
- `mmc2: Failed to initialize a non-removable card` in dmesg is the SDIO Wi-Fi slot, harmless without Wi-Fi.
- The red LED trigger can be changed in `dts/b860h-extras.dts` (`linux,default-trigger`): `activity` (CPU load,
  current), `mmc1` (eMMC I/O), `disk-activity`, `heartbeat`. Re-run `scripts/b860h-dtb-guard` as root after
  editing the installed copy in `/usr/local/share/b860h/`.
- `dpkg -i` and kernel changes done outside apt don't trigger the guard: run `sudo /usr/local/sbin/b860h-dtb-guard`.
- GPIO list: ETH LEDs `periphs-banks 14/15`, red LED 73, green LED 75, power button `aobus-banks 2`;
  avoid `periphs-banks 74` and `77` (see `legacy/B860H-GPIO-list.txt`).
- `legacy/` keeps the original hand-edited dts/dtb dump and the old userspace power-button script for reference.
  They are not used by anything here.

## Layout

```
uboot/       uboot_HG680P.bin (needed), uboot_B860H.bin (alternative), SHA256SUMS
dts/         b860h-extras.dts   overlay: LEDs + power button
scripts/     install-b860h.sh   patch a running system
             b860h-dtb-guard    apt hook: rebuild dtb, drop SD boot scripts on the eMMC
             check-emmc-uboot.sh, fix-emmc-boot.sh   around the stock /root/install-aml.sh
             write-uboot.sh / write-uboot.ps1        put the bootloader on an SD card / disk
legacy/      original dts/dtb, GPIO list, old powerStatus.sh
```
