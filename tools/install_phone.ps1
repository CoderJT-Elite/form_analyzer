<#
.SYNOPSIS
  Build a stamped release APK from committed code and install it on the Pixel.

.DESCRIPTION
  Live test #3 (2026-09-29) was recorded on a stale build without anyone
  noticing. This makes that impossible to do by accident:
    - refuses to build from a dirty tree (unless -AllowDirty)
    - runs flutter analyze + flutter test first (unless -SkipChecks)
    - stamps the APK with the git SHA / dirty flag / time (BuildInfo, shown at
      the bottom of the Profile tab)
    - installs over wireless adb and prints the SHA to look for on the phone

.PARAMETER Device
  ip:port from Developer options > Wireless debugging. The IP is stable
  (10.0.0.110) but the port changes every time, e.g. 10.0.0.110:33855.
  Omit if the phone is already connected (adb devices).

.EXAMPLE
  .\tools\install_phone.ps1 -Device 10.0.0.110:33855
#>
[CmdletBinding()]
param(
  [string]$Device,
  [switch]$AllowDirty,
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$adb = 'C:\Users\natuj\AppData\Local\Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "adb not found at $adb" }

Push-Location $repo
try {
  $sha = (git rev-parse --short HEAD).Trim()
  $dirtyFiles = @(git status --porcelain -- app | Where-Object { $_ })
  $dirty = $dirtyFiles.Count -gt 0
  if ($dirty -and -not $AllowDirty) {
    Write-Host "Uncommitted changes under app/:" -ForegroundColor Yellow
    $dirtyFiles | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
    throw "Refusing to build a test APK from a dirty tree. Commit first, or pass -AllowDirty."
  }
} finally { Pop-Location }

if ($Device) {
  Write-Host "Connecting to $Device ..."
  & $adb connect $Device
}
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice$" })
if ($devices.Count -eq 0) { throw "No adb device connected. Toggle Wireless debugging and pass -Device ip:port." }

Push-Location $app
try {
  if (-not $SkipChecks) {
    flutter analyze;  if ($LASTEXITCODE) { throw 'flutter analyze failed' }
    flutter test;     if ($LASTEXITCODE) { throw 'flutter test failed' }
  }
  $time = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  flutter build apk --release `
    "--dart-define=GIT_SHA=$sha" `
    "--dart-define=GIT_DIRTY=$($dirty.ToString().ToLower())" `
    "--dart-define=BUILD_TIME=$time"
  if ($LASTEXITCODE) { throw 'flutter build failed' }
} finally { Pop-Location }

$apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
& $adb install -r $apk
if ($LASTEXITCODE) { throw 'adb install failed' }

$label = if ($dirty) { "$sha+dirty" } else { $sha }
Write-Host ""
Write-Host "Installed build $label ($time)." -ForegroundColor Green
Write-Host "Open the Profile tab and confirm the footer says: Build $label"
