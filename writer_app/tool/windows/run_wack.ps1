<#
.SYNOPSIS
  OWNER SCRIPT (not run by the agent). Windows App Certification Kit on a Pellucid MSIX, then a summary of failures.
  Needs an ELEVATED PowerShell (appcert.exe requirement).

  powershell -ExecutionPolicy Bypass -File D:\projects\pellucid\writer_app\tool\windows\run_wack.ps1
  powershell -ExecutionPolicy Bypass -File ...\run_wack.ps1 -Msix "D:\projects\Pellucid Store Submission 1.1.0.0\pellucid-1.1.0.0.msix"

  Note: WACK installs the package temporarily to test it. For the self-signed test MSIX the certificate must be
  trusted (owner_install_test.ps1 does that). The unsigned Store package cannot be installed by WACK; test the
  signed test build (same binaries) instead.
  Output: D:\projects\.scratch\wack.xml, then parse_wack.ps1 lists the failures.
#>
[CmdletBinding()]
param(
  [string]$Msix = 'D:\projects\Pellucid Test MSIX 1.1.0.2\pellucid-1.1.0.2.msix',
  [string]$Report = 'D:\projects\.scratch\wack.xml'
)
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this in an elevated PowerShell.' }
$kit = 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe'
if (-not (Test-Path $kit)) { throw "appcert.exe not found at $kit (install the Windows SDK's App Certification Kit)." }
if (-not (Test-Path $Msix)) { throw "MSIX not found: $Msix" }
New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
& $kit reset
& $kit test -appxpackagepath $Msix -reportoutputpath $Report
"appcert exit code: $LASTEXITCODE"
& (Join-Path $PSScriptRoot 'parse_wack.ps1') -Report $Report
