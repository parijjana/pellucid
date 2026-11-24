<#
.SYNOPSIS
  Release build + MSIX packaging for Pellucid on Windows, with post-build verification.

.EXAMPLE
  # Store package (unsigned, version 1.1.0.0) into D:\projects\Pellucid Store Submission 1.1.0.0\
  .\tool\windows\build_store.ps1 -Mode store

.EXAMPLE
  # Test package (signed with the msix test cert, version 1.1.0.N) into D:\projects\Pellucid Test MSIX 1.1.0.N\
  .\tool\windows\build_store.ps1 -Mode test -TestBuild 2

Reads GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET from writer_app\.env (never printed), builds with those
dart-defines only. PELLUCID_DATA_DIR is never passed (it is a test-run switch; release builds ignore it,
and this script additionally checks app.so for any trace of it).
Refuses to overwrite an existing output .msix unless -Force.
Nothing is installed or trusted; no elevation needed.
#>
[CmdletBinding()]
param(
  [ValidateSet('store', 'test')][string]$Mode = 'test',
  [int]$TestBuild = 1,                       # test mode: version 1.1.0.<TestBuild>
  [string]$BaseVersion = '1.1.0',            # first three parts
  [string]$OutRoot = 'D:\projects',
  [switch]$Force,
  [switch]$SkipBuild                         # reuse existing build\windows\...\Release (package only)
)
$ErrorActionPreference = 'Stop'
$app = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $app

if (-not $app.Path.StartsWith('D:\', [StringComparison]::OrdinalIgnoreCase)) { throw "Run from a checkout on D:" }

# --- version and output folder -------------------------------------------------------------
if ($Mode -eq 'store') { $version = "$BaseVersion.0"; $outDir = Join-Path $OutRoot "Pellucid Store Submission $version" }
else { $version = "$BaseVersion.$TestBuild"; $outDir = Join-Path $OutRoot "Pellucid Test MSIX $version" }
$outMsix = Join-Path $outDir "pellucid-$version.msix"
if ((Test-Path $outMsix) -and -not $Force) { throw "$outMsix exists; pass -Force to overwrite (only if rebuilding from the same commit)." }

$commit = (git rev-parse --short HEAD).Trim()
$dirty = (git status --porcelain -- . ':!.env' | Out-String).Trim()
if ($dirty) { Write-Warning "Working tree has uncommitted changes; the package will not match commit $commit exactly." }

# --- secrets from .env (never echoed) ----------------------------------------------------------
$envFile = Join-Path $app '.env'
if (-not (Test-Path $envFile)) { throw ".env not found at $envFile" }
$kv = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$' -and $_ -notmatch '^\s*#') { $kv[$Matches[1]] = $Matches[2].Trim('"', "'") }
}
$cid = $kv['GOOGLE_CLIENT_ID']; $sec = $kv['GOOGLE_CLIENT_SECRET']
if (-not $cid -or $cid -like 'your_client_id*' -or -not $sec -or $sec -like 'your_client_secret*') { throw ".env has missing/placeholder GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET" }

# --- build -----------------------------------------------------------------------------------------
$rel = Join-Path $app 'build\windows\x64\runner\Release'
if (-not $SkipBuild) {
  flutter pub get
  if ($LASTEXITCODE) { throw 'flutter pub get failed' }
  # Passing the secret on the command line is unavoidable for --dart-define; output is not echoed.
  flutter build windows --release "--dart-define=GOOGLE_CLIENT_ID=$cid" "--dart-define=GOOGLE_CLIENT_SECRET=$sec"
  if ($LASTEXITCODE) { throw 'flutter build windows failed' }
}

# --- package -------------------------------------------------------------------------------------------
$tmpMsix = Join-Path $rel 'pellucid.msix'
if (Test-Path $tmpMsix) { Remove-Item $tmpMsix -Force }
$msixArgs = @('run', 'msix:create', '--build-windows', 'false', '--version', $version)
if ($Mode -eq 'store') { $msixArgs += '--store' } else { $msixArgs += @('--install-certificate', 'false') }
dart @msixArgs
if ($LASTEXITCODE) { throw 'msix:create failed' }
if (-not (Test-Path $tmpMsix)) { throw "msix output not found at $tmpMsix" }

New-Item -ItemType Directory -Force $outDir | Out-Null
Copy-Item $tmpMsix $outMsix -Force

# --- verify ------------------------------------------------------------------------------------------------
$fail = @()
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($outMsix)
try {
  $m = $zip.GetEntry('AppxManifest.xml')
  $xml = [xml]([IO.StreamReader]::new($m.Open()).ReadToEnd())
  $identVer = $xml.Package.Identity.Version
  $identName = $xml.Package.Identity.Name
  if ($identVer -ne $version) { $fail += "Identity Version is $identVer, expected $version" }
  if ($identName -ne 'OverEngineeredHobbies.Pellucid') { $fail += "Identity Name is $identName" }
  if ($Mode -eq 'store' -and -not $identVer.EndsWith('.0')) { $fail += 'Store version must end in .0' }
  $hasSig = $null -ne $zip.GetEntry('AppxSignature.p7x')
  if ($Mode -eq 'store' -and $hasSig) { $fail += 'Store package should be unsigned but has AppxSignature.p7x' }
  if ($Mode -eq 'test' -and -not $hasSig) { $fail += 'Test package should be signed (AppxSignature.p7x missing)' }
  $so = $zip.Entries | Where-Object { $_.FullName -match '(^|/)app\.so$' } | Select-Object -First 1
  if (-not $so) { $fail += 'app.so not found in package' }
  else {
    $ms = [IO.MemoryStream]::new(); $s = $so.Open(); $s.CopyTo($ms); $s.Dispose()
    $text = [Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray())
    foreach ($ph in 'YOUR_GOOGLE_CLIENT_ID', 'YOUR_GOOGLE_CLIENT_SECRET') {
      if ($text.Contains($ph)) { $fail += "placeholder $ph present in app.so" }
    }
    if (-not $text.Contains($cid)) { $fail += 'real client id NOT found in app.so (defines missing?)' }
    foreach ($bad in 'PELLUCID_DATA_DIR', 'pellucid-data-', '.scratch') {
      if ($text.Contains($bad)) { $fail += "app.so contains '$bad' (data-dir define leaked?)" }
    }
  }
} finally { $zip.Dispose() }

"Mode:            $Mode"
"Commit:          $commit$(if ($dirty) { ' (DIRTY)' })"
"Package:         $outMsix"
"Identity:        $identName $identVer"
"Signed:          $hasSig"
if ($fail) { $fail | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }; exit 1 }
Write-Host 'PASS: version, identity, signature state, real client id present, no placeholder, no data-dir define' -ForegroundColor Green
