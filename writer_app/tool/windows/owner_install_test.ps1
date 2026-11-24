<#
.SYNOPSIS
  OWNER SCRIPT (not run by the agent). Installs the Pellucid test MSIX over the installed Store 1.0.1.

.DESCRIPTION
  Step 1 (this script, run in an ELEVATED PowerShell): exports the test package's signing certificate and
  trusts it for this machine (Cert:\LocalMachine\TrustedPeople), so the self-signed test MSIX can install.
  Step 2 (same script, no elevation needed, but fine elevated): Add-AppxPackage the test MSIX. Because the
  identity name matches and the version is higher, this upgrades your installed 1.0.1 in place and keeps its data.

  Install 1.0.1 from the Store FIRST (it is what you have), create a project and connect Drive, then run:

    # elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File D:\projects\pellucid\writer_app\tool\windows\owner_install_test.ps1

  Afterwards run owner_post_upgrade_check.ps1 (non-elevated).
  To go back to the Store build later: Remove-AppxPackage OverEngineeredHobbies.Pellucid (app data of the
  package is removed with it; back up first) and reinstall from the Store.
#>
[CmdletBinding()]
param(
  [string]$Msix = 'D:\projects\Pellucid Test MSIX 1.1.0.2\pellucid-1.1.0.2.msix',
  [string]$CerOut = 'D:\projects\.scratch\pellucid_test.cer',
  [switch]$SkipTrust,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Msix)) { throw "MSIX not found: $Msix" }

$installed = Get-AppxPackage -Name 'OverEngineeredHobbies.Pellucid'
if ($installed) { "Currently installed: $($installed.PackageFullName)" } else { Write-Warning 'Pellucid is not installed (a fresh install will not test the upgrade path).' }
$ver = (Get-AuthenticodeSignature $Msix).SignerCertificate
if (-not $ver) { throw 'The MSIX has no signature (is it the Store build? use the test build).' }
"Test package: $Msix"
"Signed by:    $($ver.Subject)"
if ($installed -and [version]$installed.Version -ge [version]'1.1.0.2') { Write-Warning "Installed version $($installed.Version) is not lower than the test package; Add-AppxPackage will refuse a downgrade." }

if (-not $Yes) {
  $a = Read-Host 'Trust this certificate on this machine (LocalMachine\TrustedPeople) and install over the current Pellucid? [y/N]'
  if ($a -ne 'y') { 'Aborted.'; exit 1 }
}

if (-not $SkipTrust) {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw 'Trusting the certificate needs an elevated PowerShell. Re-run as administrator (or use -SkipTrust if already trusted).' }
  New-Item -ItemType Directory -Force (Split-Path $CerOut) | Out-Null
  [IO.File]::WriteAllBytes($CerOut, $ver.Export('Cert'))
  Import-Certificate -FilePath $CerOut -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
  "Trusted $($ver.Thumbprint) in LocalMachine\TrustedPeople. To remove later:  Remove-Item Cert:\LocalMachine\TrustedPeople\$($ver.Thumbprint)"
}

Add-AppxPackage -Path $Msix
Get-AppxPackage -Name 'OverEngineeredHobbies.Pellucid' | Select-Object Name, Version, PackageFullName | Format-List
'Installed. Launch Pellucid from the Start menu, then run owner_post_upgrade_check.ps1.'
