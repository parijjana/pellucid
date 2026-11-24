<#
.SYNOPSIS
  Reads a WACK (appcert.exe) XML report and lists the failed tests. Read-only, no elevation needed.
  parse_wack.ps1 [-Report D:\projects\.scratch\wack.xml]   exit code 0 = overall PASS, 1 = failures, 2 = unreadable.
#>
[CmdletBinding()]
param([string]$Report = 'D:\projects\.scratch\wack.xml')
if (-not (Test-Path $Report)) { Write-Host "Report not found: $Report"; exit 2 }
try { [xml]$x = Get-Content $Report -Raw } catch { Write-Host "Cannot parse $Report as XML: $_"; exit 2 }
$r = $x.REPORT
if (-not $r) { Write-Host 'No REPORT element (not a WACK report?)'; exit 2 }
"App:      $($r.APP_NAME) $($r.APP_VERSION)"
"Overall:  $($r.OVERALL_RESULT)"
$fails = @()
foreach ($req in $r.REQUIREMENTS.REQUIREMENT) {
  foreach ($t in $req.TEST) {
    if ($t.RESULT -eq 'FAIL') {
      $fails += [pscustomobject]@{
        Requirement = "$($req.NUMBER) $($req.TITLE)"
        Test        = "$($t.INDEX) $($t.NAME)"
        Optional    = $t.OPTIONAL
        Detail      = (($t.MESSAGES.MESSAGE | ForEach-Object { $_.TEXT; $_.'#text' } | Where-Object { $_ }) -join ' | ')
      }
    }
  }
}
if (-not $fails) { Write-Host 'No failed tests.' -ForegroundColor Green }
else {
  Write-Host "$($fails.Count) failed test(s):" -ForegroundColor Red
  foreach ($f in $fails) {
    Write-Host ("- [{0}] {1}  (optional={2})" -f $f.Requirement, $f.Test, $f.Optional) -ForegroundColor Red
    if ($f.Detail) { Write-Host "    $($f.Detail)" }
  }
}
if ($r.OVERALL_RESULT -eq 'PASS' -and -not $fails) { exit 0 } else { exit 1 }
