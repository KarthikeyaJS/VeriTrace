<#
.SYNOPSIS
  Builds the client hand-off package: dist\VeriTrace-client-<date>.zip
    - source code (without node_modules, build outputs, Python venv, logs, generated contract/QR files)
    - dist\VeriTrace.apk (prebuilt Android app, so the client does not need Flutter)
    - setup.ps1 / start-all.ps1 / stop-all.ps1 and START_HERE.md
  Secrets are NOT included unless -IncludeFirebaseKeys is given.

.EXAMPLE
  .\package-client.ps1                       # zip without Firebase keys (send them separately)
  .\package-client.ps1 -IncludeFirebaseKeys  # also include backend\serviceAccountKey.json, google-services.json and backend\.env
  .\package-client.ps1 -BuildApk             # rebuild the release APK first (needs the Flutter SDK)
#>
param(
  [switch]$IncludeFirebaseKeys,
  [switch]$BuildApk
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
# Stage outside the repo: IDEs watching the workspace (e.g. the VS Code Java extension) lock copied Gradle files.
$stagingRoot = Join-Path (Split-Path $root -Parent) ((Split-Path $root -Leaf) + '-package-staging')
$stage = Join-Path $stagingRoot 'VeriTrace'
$apk = Join-Path $dist 'VeriTrace.apk'
$builtApk = Join-Path $root 'mobile\build\app\outputs\flutter-apk\app-release.apk'
New-Item -ItemType Directory -Force $dist | Out-Null

# ---------------------------------------------------------------- APK
if ($BuildApk) {
  Write-Host '>> Building release APK (default server http://127.0.0.1:3000 = USB mode)' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'mobile')
  try { flutter build apk --release --target-platform android-arm64,android-x64 --dart-define=API_BASE_URL=http://127.0.0.1:3000; if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' } } finally { Pop-Location }
}
if (Test-Path $builtApk) {
  if (-not (Test-Path $apk) -or (Get-Item $builtApk).LastWriteTime -gt (Get-Item $apk).LastWriteTime) { Copy-Item $builtApk $apk -Force }
}
if (-not (Test-Path $apk)) { throw 'No APK found. Run with -BuildApk (needs the Flutter SDK).' }

# ---------------------------------------------------------------- stage files
Write-Host '>> Collecting files' -ForegroundColor Cyan
if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
$excludeDirs = @('node_modules', '.dart_tool', 'build', '.gradle', '.venv', 'logs', 'dist', 'tools', 'artifacts', 'cache',
  '.firebase', '.idea', '.vscode', '__pycache__', '.pytest_cache', 'typechain-types', 'coverage', '.git',
  (Join-Path $root 'ml\data'), (Join-Path $root 'demo\qr'))
$excludeFiles = @('*.log', '*.apk', '*.zip', 'local.properties', '.flutter-plugins', '.flutter-plugins-dependencies',
  'contract.json', 'BUILD_PROMPT.md', 'serviceAccountKey.json', 'google-services.json', '.env')
& robocopy $root $stage /E /NFL /NDL /NJH /NJS /NP /XD $excludeDirs /XF $excludeFiles | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
New-Item -ItemType Directory -Force (Join-Path $stage 'demo\qr') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $stage 'dist') | Out-Null
Copy-Item $apk (Join-Path $stage 'dist\VeriTrace.apk')

if ($IncludeFirebaseKeys) {
  foreach ($pair in @(
      @('backend\serviceAccountKey.json', 'backend\serviceAccountKey.json'),
      @('mobile\android\app\google-services.json', 'mobile\android\app\google-services.json'),
      @('backend\.env', 'backend\.env'))) {
    $src = Join-Path $root $pair[0]
    if (Test-Path $src) { Copy-Item $src (Join-Path $stage $pair[1]) -Force; Write-Host "   included $($pair[0])" -ForegroundColor Yellow }
  }
} else {
  Write-Host '   Firebase keys NOT included - send backend\serviceAccountKey.json to the client separately.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- zip
$zip = Join-Path $dist ("VeriTrace-client-{0}.zip" -f (Get-Date -Format 'yyyyMMdd'))
if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host '>> Creating zip' -ForegroundColor Cyan
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stagingRoot -Recurse -Force
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "`nPackage ready: $zip ($size MB)" -ForegroundColor Green
Write-Host "The client unzips it, reads VeriTrace\START_HERE.md, runs setup.ps1 once and start-all.ps1 each time."
