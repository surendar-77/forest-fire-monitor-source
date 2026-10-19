# Builds the web app with a fresh build id and publishes it to Firebase
# Hosting. Installed copies of the app compare their build id with
# build_id.txt on the site and offer "Update" when it changes.
#
#   powershell -ExecutionPolicy Bypass -File tool\deploy_web.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$buildId = Get-Date -Format 'yyyyMMdd-HHmm'
Write-Host "Building web app, build $buildId"
flutter build web --release --no-web-resources-cdn --dart-define=BUILD_ID=$buildId
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

# Written after the build so it always matches the id compiled into the app.
[System.IO.File]::WriteAllText((Join-Path $PWD 'build/web/build_id.txt'), $buildId)

firebase deploy --only hosting --project forest-fire-3d2f0
if ($LASTEXITCODE -ne 0) { throw 'firebase deploy failed' }
Write-Host "Published build $buildId to https://forest-fire-3d2f0.web.app"
