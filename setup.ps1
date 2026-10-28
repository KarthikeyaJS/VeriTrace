<#
.SYNOPSIS
  One-time setup of VeriTrace on a Windows laptop. Safe to run again at any time.

  1. Checks Node.js (20+), and optionally Python (ML service) and Flutter (only to rebuild the app)
  2. Installs the npm dependencies (repo root + backend)
  3. Creates the ML service's Python environment (ml\.venv) if Python is available
  4. Downloads Android platform-tools (adb) into tools\ if adb is not installed
  5. Checks the Firebase key file and creates backend\.env if it does not exist

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>
param(
  [switch]$SkipMl,
  [switch]$SkipAdbDownload
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$env:NODE_ENV = 'development'   # make sure npm installs devDependencies (Hardhat)
$problems = New-Object System.Collections.Generic.List[string]

function Step($text) { Write-Host "`n>> $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "   OK  $text" -ForegroundColor Green }
function Warn($text) { Write-Host "   !!  $text" -ForegroundColor Yellow }
function Fail($text) { Write-Host "   XX  $text" -ForegroundColor Red; $problems.Add($text) }

function Invoke-Checked([string]$what, [scriptblock]$block) {
  & $block
  if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" }
}

# ---------------------------------------------------------------- 1. tools
Step 'Checking tools'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Node.js is not installed. Install the LTS version (20 or newer) from https://nodejs.org and run setup again.' }
$nodeVersion = (& node -v).Trim()
if ([int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 20) { throw "Node.js $nodeVersion is too old. Install 20 or newer from https://nodejs.org." }
Ok "Node.js $nodeVersion"

$python = $null
foreach ($candidate in 'python', 'py') {
  # `python` may be the Microsoft Store alias (prints an error instead of a version) - treat that as "not installed".
  if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
  try { $version = (& $candidate --version 2>&1) -join ' ' } catch { $version = '' }
  if ($version -match 'Python 3\.(1[0-9]|[2-9][0-9])') { $python = $candidate; break }
}
if ($python) { Ok "Python: $((& $python --version 2>&1))" } else { Warn 'Python 3.10+ not found - the optional ML service will be skipped (https://www.python.org/downloads/).' }

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutter) { Ok 'Flutter SDK found (the app can be rebuilt from source)' } else { Ok 'Flutter SDK not installed - the prebuilt app dist\VeriTrace.apk will be used' }

# ---------------------------------------------------------------- 2. npm
Step 'Installing Node.js packages (1-3 minutes the first time)'
Push-Location $root
try {
  if (Test-Path 'package-lock.json') { Invoke-Checked 'npm ci (root)' { npm ci --no-audit --no-fund } } else { Invoke-Checked 'npm install (root)' { npm install --no-audit --no-fund } }
  Ok 'root packages (Hardhat, contract tooling)'
  Push-Location 'backend'
  try {
    if (Test-Path 'package-lock.json') { Invoke-Checked 'npm ci (backend)' { npm ci --no-audit --no-fund } } else { Invoke-Checked 'npm install (backend)' { npm install --no-audit --no-fund } }
  } finally { Pop-Location }
  Ok 'backend packages'
} finally { Pop-Location }

# ---------------------------------------------------------------- 3. ML
if ($python -and -not $SkipMl) {
  Step 'Setting up the ML service (Python virtual environment, 1-3 minutes)'
  # Optional component: any failure here only disables ML, it never stops the setup.
  try {
    $mlDir = Join-Path $root 'ml'
    $venvPython = Join-Path $mlDir '.venv\Scripts\python.exe'
    # A venv copied from another PC points at that PC's Python and does not run here: rebuild it.
    $venvOk = $false
    if (Test-Path $venvPython) { try { & $venvPython -c "import sys" 2>$null; $venvOk = ($LASTEXITCODE -eq 0) } catch { $venvOk = $false } }
    if (-not $venvOk) {
      if (Test-Path (Join-Path $mlDir '.venv')) { Write-Host '   ..  rebuilding ml\.venv (copied from another computer)'; Remove-Item (Join-Path $mlDir '.venv') -Recurse -Force }
      Invoke-Checked 'python -m venv' { & $python -m venv (Join-Path $mlDir '.venv') }
    }
    Invoke-Checked 'pip install' { & $venvPython -m pip install -q --disable-pip-version-check -r (Join-Path $mlDir 'requirements.txt') }
    Push-Location $mlDir
    try {
      # The included model was trained with the tested library versions; retrain if this Python cannot load it.
      $loads = $false
      try { & $venvPython -c "import joblib; joblib.load('model/isolation_forest.joblib')" 2>$null; $loads = ($LASTEXITCODE -eq 0) } catch { $loads = $false }
      if (-not $loads) {
        Write-Host '   ..  training the ML model for this Python version (about 1 minute)'
        Invoke-Checked 'train model' { & $venvPython train.py | Out-Null }
      }
    } finally { Pop-Location }
    Ok 'ML service ready'
  } catch {
    Warn "ML service setup failed ($($_.Exception.Message)). VeriTrace works without it; the ML check will show 'not run'."
  }
}

# ---------------------------------------------------------------- 4. adb
Step 'Checking adb (Android platform-tools, used to install the app on the phone)'
$adb = Get-Command adb -ErrorAction SilentlyContinue
$adbPath = if ($adb) { $adb.Source } else {
  @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'), (Join-Path $root 'tools')) |
    Where-Object { $_ } | ForEach-Object { Join-Path $_ 'platform-tools\adb.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($adbPath) {
  Ok "adb: $adbPath"
} elseif ($SkipAdbDownload) {
  Warn 'adb not found (download skipped). The app can still be installed by copying dist\VeriTrace.apk to the phone.'
} else {
  $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
  Write-Host '   ..  downloading Android platform-tools from dl.google.com (about 10 MB)'
  Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath (Join-Path $root 'tools') -Force
  Remove-Item $zip -Force
  Ok "adb installed in tools\platform-tools"
}

# ---------------------------------------------------------------- 5. Firebase + .env
Step 'Checking Firebase configuration'
$keyFile = Join-Path $root 'backend\serviceAccountKey.json'
$envFile = Join-Path $root 'backend\.env'
if (Test-Path $keyFile) {
  $key = Get-Content $keyFile -Raw | ConvertFrom-Json
  Ok "service account key for Firebase project '$($key.project_id)'"
  if (-not (Test-Path $envFile)) {
    $webKey = ''
    $gs = Join-Path $root 'mobile\android\app\google-services.json'
    if (Test-Path $gs) { $webKey = ((Get-Content $gs -Raw | ConvertFrom-Json).client[0].api_key[0].current_key) }
    $text = Get-Content (Join-Path $root 'backend\.env.example') -Raw
    $text = $text -replace '(?m)^FIREBASE_PROJECT_ID=.*$', "FIREBASE_PROJECT_ID=$($key.project_id)" -replace '(?m)^FIREBASE_WEB_API_KEY=.*$', "FIREBASE_WEB_API_KEY=$webKey"
    [IO.File]::WriteAllText($envFile, $text, (New-Object Text.UTF8Encoding($false)))
    Ok 'created backend\.env'
    if (-not $webKey) { Warn 'FIREBASE_WEB_API_KEY is empty in backend\.env - only needed for "npm run e2e" (ask the developer for it).' }
  } else {
    Ok 'backend\.env already exists (left unchanged)'
  }
} else {
  Fail 'backend\serviceAccountKey.json is missing. Copy the Firebase key file you received from the developer into the backend folder (exact name: serviceAccountKey.json), then run setup again.'
}

# ---------------------------------------------------------------- summary
Step 'Summary'
if (Test-Path (Join-Path $root 'dist\VeriTrace.apk')) { Ok 'prebuilt app: dist\VeriTrace.apk' }
elseif (-not $flutter) { Fail 'dist\VeriTrace.apk is missing and Flutter is not installed - ask the developer for the APK.' }
if ($problems.Count) {
  Write-Host "`nSetup is NOT complete:" -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}
Write-Host "`nSetup complete. Every time you want to run VeriTrace:" -ForegroundColor Green
Write-Host '  1. Connect the phone by USB (USB debugging on)'
Write-Host '  2. powershell -ExecutionPolicy Bypass -File .\start-all.ps1'
Write-Host '  See START_HERE.md for the full guide.'
