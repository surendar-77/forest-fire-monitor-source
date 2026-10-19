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

# Give the app's scripts a new address each version, so no browser can keep
# running a saved copy of an older one (index.html is served no-cache).
$bootstrap = Join-Path $PWD 'build/web/flutter_bootstrap.js'
$js = [System.IO.File]::ReadAllText($bootstrap)
if ($js -notmatch '"mainJsPath":"main\.dart\.js"') { throw 'mainJsPath not found in flutter_bootstrap.js' }
$js = $js.Replace('"mainJsPath":"main.dart.js"', ('"mainJsPath":"main.dart.js?v=' + $buildId + '"'))
[System.IO.File]::WriteAllText($bootstrap, $js)

$index = Join-Path $PWD 'build/web/index.html'
$html = [System.IO.File]::ReadAllText($index)
if ($html -notmatch 'src="flutter_bootstrap\.js"') { throw 'flutter_bootstrap.js script tag not found in index.html' }
$html = $html.Replace('src="flutter_bootstrap.js"', ('src="flutter_bootstrap.js?v=' + $buildId + '"'))
[System.IO.File]::WriteAllText($index, $html)

# Firebase Hosting on the free plan refuses executables; APKs are published
# from the Cloudflare Worker instead (tool/release_apk.ps1).
Get-ChildItem build/web -Recurse -Include *.apk,*.exe -ErrorAction SilentlyContinue | Remove-Item -Force

firebase deploy --only hosting --project forest-fire-3d2f0
if ($LASTEXITCODE -ne 0) { throw 'firebase deploy failed' }
Write-Host "Published build $buildId to https://forest-fire-3d2f0.web.app"
