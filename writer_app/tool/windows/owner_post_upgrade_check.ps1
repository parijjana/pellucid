<#
.SYNOPSIS
  OWNER SCRIPT (not run by the agent). Non-elevated, read-only. After upgrading 1.0.1 -> 1.1.0.x and launching
  Pellucid once, checks that Drive credentials were moved out of the plaintext files. Prints PASS/FAIL.

  powershell -ExecutionPolicy Bypass -File D:\projects\pellucid\writer_app\tool\windows\owner_post_upgrade_check.ps1

  Checks
   1. shared_preferences.json (under the package's LocalCache\Roaming\overengineeredhobbies\Pellucid) has no
      google_drive_* keys, no google_client_id_pref, no google_client_secret_pref.
   2. settings.db has no custom client secret / id stored (settings.google_client_secret / google_client_id empty).
  It opens settings.db read-only (a copy, so the app's file is untouched). Needs python (sqlite3 module) or sqlite3.exe;
  without either, check 2 is reported as SKIPPED. It never prints secret values.
  Whether Drive is still connected and Credential Manager holds the tokens is for you to look at in the app.
#>
$ErrorActionPreference = 'Stop'
$fail = 0
function Pass($m) { Write-Host "PASS  $m" -ForegroundColor Green }
function Fail($m) { Write-Host "FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Skip($m) { Write-Host "SKIP  $m" -ForegroundColor Yellow }

$pkgs = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter 'OverEngineeredHobbies.Pellucid_*' -ErrorAction SilentlyContinue
if (-not $pkgs) { Fail 'No OverEngineeredHobbies.Pellucid_* package folder under %LOCALAPPDATA%\Packages (is the MSIX installed and launched once?)'; exit 1 }
$pkg = $pkgs | Select-Object -First 1
"Package folder: $($pkg.FullName)"
$inst = Get-AppxPackage -Name 'OverEngineeredHobbies.Pellucid'
if ($inst) { "Installed version: $($inst.Version)" }

$data = Join-Path $pkg.FullName 'LocalCache\Roaming\overengineeredhobbies\Pellucid'
$prefs = Join-Path $data 'shared_preferences.json'
if (-not (Test-Path $prefs)) { Skip "shared_preferences.json not found at $prefs (nothing stored there: acceptable if the app wrote no prefs)" }
else {
  $json = Get-Content $prefs -Raw | ConvertFrom-Json
  $keys = @($json.PSObject.Properties.Name)
  "shared_preferences.json keys ($($keys.Count)): $($keys -join ', ')"
  $bad = $keys | Where-Object { $_ -match 'google_drive_' -or $_ -match 'google_client_id_pref' -or $_ -match 'google_client_secret_pref' }
  if ($bad) { Fail "forbidden keys still in shared_preferences.json: $($bad -join ', ')" }
  else { Pass 'no google_drive_*, google_client_id_pref or google_client_secret_pref keys in shared_preferences.json' }
}

# settings.db: location is the app-support dir; search the data folder.
$db = Get-ChildItem $pkg.FullName -Recurse -Filter 'settings.db' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $db) { Skip 'settings.db not found' }
else {
  $tmp = Join-Path $env:TEMP "pellucid_settings_copy_$PID.db"
  Copy-Item $db.FullName $tmp -Force
  $wal = $db.FullName + '-wal'; if (Test-Path $wal) { Copy-Item $wal ($tmp + '-wal') -Force }
  $q = "SELECT length(coalesce(google_client_secret,'')), length(coalesce(google_client_id,'')) FROM settings LIMIT 1;"
  $out = $null
  $py = Get-Command python -ErrorAction SilentlyContinue
  $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
  try {
    if ($py) {
      $code = "import sqlite3,sys; c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True); r=c.execute(sys.argv[2]).fetchone(); print('%d|%d'%(r[0],r[1]) if r else 'none')"
      $out = (& python -I -c $code $tmp $q) -join ''
    } elseif ($sqlite) { $out = (& sqlite3 -readonly -separator '|' $tmp $q) -join '' }
  } catch { Write-Warning "sqlite read failed: $_" }
  Remove-Item $tmp, ($tmp + '-wal') -Force -ErrorAction SilentlyContinue
  if (-not $out) { Skip 'neither python nor sqlite3 usable, or the query failed; check settings.db by hand' }
  elseif ($out -eq 'none') { Pass 'settings table has no row (nothing stored)' }
  else {
    $secLen, $idLen = $out.Split('|')
    if ([int]$secLen -gt 0) { Fail "settings.db still stores a custom client secret ($secLen chars; value not shown)" }
    else { Pass 'settings.db stores no custom client secret' }
    if ([int]$idLen -gt 0) { Write-Host "NOTE  settings.db has a custom client id ($idLen chars). Only the secret is required to be gone; the id is not secret." }
  }
}

if ($fail -eq 0) { Write-Host "`nOVERALL: PASS" -ForegroundColor Green; exit 0 }
Write-Host "`nOVERALL: FAIL ($fail)" -ForegroundColor Red; exit 1
