<#
.SYNOPSIS
  Prepare a freshly flashed Armbian SD card (Windows) so the B860H boots it with all features at once.

.DESCRIPTION
  Run after flashing the Armbian image. Point it at the card's BOOT (FAT) drive:

    .\scripts\prepare-sd.ps1 -Drive E:

  It does three plain file operations on that drive:
    1. copies uboot\uboot_HG680P.bin as u-boot.ext (the old u-boot.ext is kept as u-boot.ext.orig)
    2. copies dtb\b860h.dtb to the drive root (stock P212 dtb of the kernel + LED/power-button overlay)
    3. makes extlinux\extlinux.conf use it: every active FDT line is commented out and
       "FDT /b860h.dtb" is added

  -SmallUboot  copy the smaller uboot\u-boot.ext (646 KB) instead of the HG680P image.

  After the first boot, run b860h-setup.sh on the box: it rebuilds /boot/b860h.dtb from the dtb of the
  kernel that is really installed and keeps it up to date after upgrades.
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$Drive,
	[switch]$SmallUboot
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
if (-not $PSScriptRoot) { $repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$root = $Drive
if ($root -match '^[A-Za-z]:$') { $root += '\' }
$conf = Join-Path $root 'extlinux\extlinux.conf'
if (-not (Test-Path $conf)) { throw "$conf not found: -Drive must be the BOOT (FAT) drive of a freshly flashed Armbian card." }

$ubootSrc = if ($SmallUboot) { Join-Path $repo 'uboot\u-boot.ext' } else { Join-Path $repo 'uboot\uboot_HG680P.bin' }
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
$added = $false
foreach ($l in $lines) {
	if ($l -match '^FDT\s') { $out.Add('#' + $l); continue }
	$out.Add($l)
	if (-not $added -and $l -match '^INITRD\s') { $out.Add('FDT /b860h.dtb'); $added = $true }
}
if (-not $added) { throw "no INITRD line in $conf; add 'FDT /b860h.dtb' by hand" }
[IO.File]::WriteAllText($conf, ($out -join $nl), (New-Object Text.UTF8Encoding($false)))
Write-Host 'extlinux.conf: FDT /b860h.dtb is now the active dtb'
Write-Host ''
Select-String -Path $conf -Pattern '^#?FDT' | ForEach-Object { '  ' + $_.Line }
Write-Host ''
Write-Host 'Done. Eject the card, put it in the box and power on.'
