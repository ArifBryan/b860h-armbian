<#
.SYNOPSIS
  Write the HG680P U-Boot image into the bootloader area of an SD card (Windows).

.DESCRIPTION
  The B860H only boots Armbian with this bootloader. Run this after flashing the Armbian image
  to the SD card (balenaEtcher, Rufus, ...). It writes bytes 0-441 and sectors 1-8191 only; the
  partition table and everything from 4 MB on stay untouched.

  Run from an elevated PowerShell:
    .\write-uboot.ps1 -DiskNumber 3
    .\write-uboot.ps1 -ImageFile .\armbian.img      # test on a plain file

  If Windows denies the write, take the disk offline first:
    Set-Disk -Number 3 -IsOffline $true     (and back online afterwards)
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory, ParameterSetName = 'Disk')][int]$DiskNumber,
	[Parameter(Mandatory, ParameterSetName = 'File')][string]$ImageFile,
	[string]$Bin
)
$ErrorActionPreference = 'Stop'
if (-not $Bin) {
	$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
	$Bin = Join-Path $root '..\uboot\uboot_HG680P.bin'
}

$data = [IO.File]::ReadAllBytes($Bin)
if ($data.Length -ne 4194304) { throw "$Bin is not a 4 MiB image" }

if ($PSCmdlet.ParameterSetName -eq 'Disk') {
	$id = [Security.Principal.WindowsIdentity]::GetCurrent()
	if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		throw 'Run this from an elevated (administrator) PowerShell.'
	}
	$d = Get-Disk -Number $DiskNumber
	if ($d.IsSystem -or $d.IsBoot) { throw "Disk $DiskNumber is a system/boot disk." }
	if ($d.BusType -notin 'USB', 'SD', 'MMC') { throw "Disk $DiskNumber is on bus '$($d.BusType)', not a USB/SD card reader." }
	if ($d.Size -gt 256GB) { throw "Disk $DiskNumber is larger than 256 GB; it is probably not your SD card." }
	Write-Host ("Disk {0}: {1}  {2:N1} GB  ({3})" -f $d.Number, $d.FriendlyName, ($d.Size / 1GB), $d.BusType)
	$ans = Read-Host "Type the disk number ($DiskNumber) to write the bootloader"
	if ($ans -ne "$DiskNumber") { throw 'Aborted.' }
	$path = "\\.\PhysicalDrive$DiskNumber"
} else {
	$path = (Resolve-Path $ImageFile).Path
	if ((Get-Item $path).Length -lt 4194304) { throw "$path is smaller than 4 MiB" }
}

$fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite, 512, [IO.FileOptions]::WriteThrough)
try {
	$sec0 = New-Object byte[] 512
	$fs.Position = 0
	$read = 0
	while ($read -lt 512) {
		$n = $fs.Read($sec0, $read, 512 - $read)
		if ($n -le 0) { throw 'Could not read sector 0.' }
		$read += $n
	}
	[Array]::Copy($data, 0, $sec0, 0, 442)          # boot code only; keep partition table
	$fs.Position = 0
	$fs.Write($sec0, 0, 512)
	$fs.Position = 512
	$fs.Write($data, 512, $data.Length - 512)        # sectors 1..8191
	$fs.Flush()
} finally {
	$fs.Dispose()
}
Write-Host "Bootloader written to $path."
