<#
.SYNOPSIS
  Prepare a freshly flashed Armbian SD card (Windows) so the B860H boots it with all features at once.

.DESCRIPTION
  Run after flashing the Armbian image. Point it at the card's BOOT (FAT) drive:

    .\scripts\prepare-sd.ps1 -Drive E:

  It does three plain file operations on that drive:
    1. copies uboot\u-boot.ext (646 KB raw U-Boot) as u-boot.ext (an existing one is kept as u-boot.ext.orig)
    2. copies dtb\b860h.dtb to the drive root (stock P212 dtb of the kernel + LED/power-button overlay)
    3. makes extlinux\extlinux.conf use it: every active FDT line is commented out and
       "FDT /b860h.dtb" is added

  -Hg680pUboot copy the 4 MB uboot\uboot_HG680P.bin as u-boot.ext instead. Not the default: that file
               starts with zeros and a box that has to `go` into it hangs in the bootloader.
  -SmallUboot  accepted for compatibility; the small file is the default now.
  -StockDtb    make extlinux use the image's own stock dtb (/dtb/amlogic/meson-gxl-s905x-p212.dtb)
               instead of b860h.dtb: a diagnostic switch, no LEDs / power button. Run the script
               again without it to go back.

  After the first boot, run b860h-setup.sh on the box: it rebuilds /boot/b860h.dtb from the dtb of the
  kernel that is really installed and keeps it up to date after upgrades.
#>
[CmdletBinding()]
param(
	[string]$Drive,
	[switch]$SmallUboot,
	[switch]$Hg680pUboot,
	[switch]$StockDtb
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
if (-not $PSScriptRoot) { $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }

# No -Drive given: find the freshly flashed Armbian BOOT drive by itself.
if (-not $Drive) {
	$found = @([IO.DriveInfo]::GetDrives() | Where-Object {
		$_.IsReady -and $_.Name -ne ($env:SystemDrive + '\')
	} | Where-Object {
		(Test-Path (Join-Path $_.Name 'extlinux\extlinux.conf')) -and
		((Test-Path (Join-Path $_.Name 'Image')) -or (Test-Path (Join-Path $_.Name 'uInitrd')))
	})
	if ($found.Count -eq 0) { throw 'No Armbian BOOT drive found. Flash the image first and re-insert the card, or pass -Drive E:' }
	if ($found.Count -eq 1) {
		$Drive = $found[0].Name
		Write-Host "Found the Armbian BOOT drive: $Drive ($($found[0].VolumeLabel))"
	} else {
		$found | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Name, $_.VolumeLabel) }
		$Drive = Read-Host 'More than one Armbian BOOT drive found. Type the drive letter to use'
	}
}
$Drive = $Drive.TrimEnd('\')
if ($Drive.Length -eq 1) { $Drive += ':' }
$root = $Drive
if ($root -match '^[A-Za-z]:$') { $root += '\' }
$conf = Join-Path $root 'extlinux\extlinux.conf'
if (-not (Test-Path $conf)) { throw "$conf not found: -Drive must be the BOOT (FAT) drive of a freshly flashed Armbian card." }

# The box's boot script runs `go 0x1000000` on u-boot.ext, so it must be a raw ARM64 U-Boot: the 646 KB
# uboot\u-boot.ext. The 4 MB uboot_HG680P.bin is an eMMC-head image that starts with zeros; as
# u-boot.ext it leaves the box hanging in the bootloader (tested), so it is opt-in only.
$null = $SmallUboot   # kept so old command lines still work; the small file is the default
$ubootSrc = if ($Hg680pUboot) { Join-Path $repo 'uboot\uboot_HG680P.bin' } else { Join-Path $repo 'uboot\u-boot.ext' }
$dtbSrc = Join-Path $repo 'dtb\b860h.dtb'
foreach ($p in $ubootSrc, $dtbSrc) { if (-not (Test-Path $p)) { throw "missing $p" } }

# 1. bootloader as u-boot.ext
$ext = Join-Path $root 'u-boot.ext'
if ((Test-Path $ext) -and -not (Test-Path "$ext.orig")) { Copy-Item $ext "$ext.orig" }
Copy-Item $ubootSrc $ext -Force
Write-Host ("u-boot.ext   <- {0} ({1:N0} bytes)" -f (Split-Path -Leaf $ubootSrc), (Get-Item $ext).Length)

# 2. dtb
Copy-Item $dtbSrc (Join-Path $root 'b860h.dtb') -Force
Write-Host ("b860h.dtb    <- dtb\b860h.dtb ({0:N0} bytes)" -f (Get-Item (Join-Path $root 'b860h.dtb')).Length)

# 3. extlinux.conf: keep the file's own line endings, comment active FDT lines, add ours
$text = [IO.File]::ReadAllText($conf)
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $text -split "`r?`n"
$out = New-Object System.Collections.Generic.List[string]
$hasOurs = $false
$fdtPath = if ($StockDtb) { '/dtb/amlogic/meson-gxl-s905x-p212.dtb' } else { '/b860h.dtb' }
$fdtRegex = [regex]::Escape($fdtPath)
# Armbian images differ in style: "INITRD /uInitrd" / "FDT ..." (upper case, no indent) or
# "  initrd /uInitrd" / "  fdt ..." (lower case, indented). Accept both and copy the style.
foreach ($l in $lines) {
	if ($l -match "^\s*fdt\s+$fdtRegex\s*$") {
		# already ours (script run before): keep exactly one
		if (-not $hasOurs) { $out.Add($l); $hasOurs = $true }
		continue
	}
	if ($l -match '^\s*fdt\s') { $out.Add('#' + $l); continue }
	$out.Add($l)
	if (-not $hasOurs -and $l -match '^(\s*)(initrd)\s') {
		$indent = $Matches[1]
		$key = if ($Matches[2] -cmatch '^[A-Z]+$') { 'FDT' } else { 'fdt' }
		$out.Add("$indent$key $fdtPath"); $hasOurs = $true
	}
}
if (-not $hasOurs) { throw "no initrd line in $conf; add 'fdt $fdtPath' by hand" }
[IO.File]::WriteAllText($conf, ($out -join $nl), (New-Object Text.UTF8Encoding($false)))
Write-Host "extlinux.conf: FDT $fdtPath is now the active dtb"
Write-Host ''
Select-String -Path $conf -Pattern '^#?\s*fdt\s' | ForEach-Object { '  ' + $_.Line }
Write-Host ''
Write-Host 'Done. Eject the card, put it in the box and power on.'
