# Builds the Android APK and publishes it as an update: installed copies of
# the app (built with this script) see "App version X is available" and
# download it from the site.
#
#   powershell -ExecutionPolicy Bypass -File tool\release_apk.ps1 -Notes "What changed"
#
# Bump `version:` in pubspec.yaml first (the +N build number must go up).
# Signed with android/key.properties (C:\secure\forest-fire-upload.jks):
# every update must use that same key or phones refuse to install it.

param([string]$Notes = "")

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)\+([0-9]+)'
if (-not $line) { throw 'version: X.Y.Z+N not found in pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value
$build = [int]$line.Matches[0].Groups[2].Value
if (-not (Test-Path android/key.properties)) { throw 'android/key.properties missing (release signing key)' }

$published = Join-Path $PWD 'releases/apk/version.json'
if (Test-Path $published) {
  $last = Get-Content $published -Raw | ConvertFrom-Json
  if ($build -le [int]$last.build) { throw "Build $build is not newer than the published build $($last.build). Bump pubspec.yaml." }
}

Write-Host "Building APK $version (build $build)"
# arm64 only: every phone from the last ~8 years, and a third of the size of
# the universal APK (Workers static assets allow files up to 25 MiB).
flutter build apk --release --split-per-abi --target-platform android-arm64 `
  --dart-define=APP_BUILD=$build --dart-define=APP_VERSION=$version
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

$name = "ForestFireMonitor-$version.apk"
New-Item -ItemType Directory -Force releases/apk | Out-Null
Get-ChildItem releases/apk -Filter '*.apk' | Remove-Item   # keep only the latest on the site
$apk = 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
if ((Get-Item $apk).Length -gt 25MB) { throw 'APK over 25 MiB: too big for Workers static assets' }
Copy-Item $apk "releases/apk/$name"
Copy-Item "releases/apk/$name" "$env:USERPROFILE\Downloads\$name"

$json = @{ build = $build; version = $version; path = "apk/$name"; notes = $Notes } | ConvertTo-Json
# UTF-8 without a byte-order mark (Set-Content -Encoding utf8 adds one).
[System.IO.File]::WriteAllText($published, $json, (New-Object System.Text.UTF8Encoding $false))

# Publish from the Cloudflare Worker's static assets (Firebase Hosting on
# the free plan refuses .apk files).
$assets = 'worker/public/apk'
New-Item -ItemType Directory -Force $assets | Out-Null
Get-ChildItem $assets -File | Remove-Item
Copy-Item releases/apk/* $assets/ -Force
Push-Location worker
npx wrangler deploy
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw 'wrangler deploy failed' }
Write-Host "Published $name; installed apps will offer the update."
