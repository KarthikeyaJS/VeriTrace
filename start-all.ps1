<#
.SYNOPSIS
  Starts the whole VeriTrace stack, each part in its own window:
    T1 Hardhat node  ->  T2 deploy + seed (npm run reset-demo)  ->  T3 backend  ->  T4 ML service  ->  T5 Flutter app on the phone
  Output of every window is also written to logs\*.log.

.EXAMPLE
  .\start-all.ps1                 # phone on USB: backend reached through `adb reverse` (no firewall change needed)
  .\start-all.ps1 -Wifi           # phone reaches http://<LAN-IP>:3000 over Wi-Fi (needs firewall rule + Private network)
  .\start-all.ps1 -Restart        # stop anything already listening on 8545/3000/8000 first
  .\start-all.ps1 -NoApp -NoMl    # servers only, no ML service
  .\start-all.ps1 -NoReset        # keep current chain + Firestore data (only if T1 was NOT restarted)
#>
param(
  [switch]$Wifi,
  [switch]$Restart,
  [switch]$NoApp,
  [switch]$NoMl,
  [switch]$NoReset,
  [string]$DeviceId
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'

function Step($text) { Write-Host "`n>> $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "   OK  $text" -ForegroundColor Green }
function Warn($text) { Write-Host "   !!  $text" -ForegroundColor Yellow }

function Test-Port([int]$port) {
  return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-Port([int]$port, [int]$seconds, [string]$what) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Port $port) { Ok "$what is listening on port $port"; return $true }
    Start-Sleep -Milliseconds 500
  }
  Warn "$what did not open port $port within $seconds s - check its window / logs\"
  return $false
}

# Opens a new PowerShell window that runs $command in $dir, shows the output and copies it to $log (UTF-8).
function Start-Window([string]$title, [string]$dir, [string]$command, [string]$log) {
  $script = @"
`$host.UI.RawUI.WindowTitle = 'VeriTrace $title'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
`$env:NODE_ENV = 'development'
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
Set-Location '$dir'
Write-Host '==== VeriTrace $title ====' -ForegroundColor Cyan
Write-Host '$command' -ForegroundColor DarkGray
`$w = New-Object IO.StreamWriter('$log', `$false, (New-Object Text.UTF8Encoding(`$false)))
`$w.AutoFlush = `$true
cmd /c "$command 2>&1" | ForEach-Object { `$_; `$w.WriteLine(`$_) }
`$w.Close()
Write-Host ''
Write-Host '[$title stopped - close this window when done]' -ForegroundColor Yellow
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  Start-Process powershell.exe -ArgumentList '-NoExit', '-EncodedCommand', $encoded | Out-Null
}

# ---------------------------------------------------------------- checks
Step 'Checking prerequisites'
if (-not (Test-Path (Join-Path $root 'node_modules\.bin\hardhat.cmd'))) { throw 'Run "npm install" in the repo root first.' }
if (-not (Test-Path (Join-Path $root 'backend\node_modules'))) { throw 'Run "npm --prefix backend install" first.' }
if (-not (Test-Path (Join-Path $root 'backend\.env'))) { throw 'backend\.env is missing - copy backend\.env.example and fill it in (docs\SETUP.md).' }
$mlPython = Join-Path $root 'ml\.venv\Scripts\python.exe'
if (-not $NoMl -and -not (Test-Path $mlPython)) { Warn 'ml\.venv not found - skipping the ML service (see ml\README.md).'; $NoMl = $true }
Ok 'dependencies and backend\.env present'

$ports = @{ 8545 = 'Hardhat node'; 3000 = 'backend'; 8000 = 'ML service' }
foreach ($port in $ports.Keys) {
  if (Test-Port $port) {
    if ($Restart) {
      $owner = (Get-NetTCPConnection -LocalPort $port -State Listen).OwningProcess | Select-Object -Unique
      foreach ($p in $owner) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
      Ok "stopped old $($ports[$port]) on port $port"
    } else {
      throw "Port $port ($($ports[$port])) is already in use. Close that window, or re-run with -Restart."
    }
  }
}
Start-Sleep -Seconds 1

# ---------------------------------------------------------------- T1 chain
Step 'T1  Hardhat node (local blockchain, port 8545)'
Start-Window 'T1 - Hardhat node' $root 'npx hardhat node --hostname 0.0.0.0' (Join-Path $logs 't1-hardhat.log')
if (-not (Wait-Port 8545 120 'Hardhat node')) { throw 'Blockchain did not start.' }

# ---------------------------------------------------------------- T3 backend (hot-reloads contract.json, so it can start now)
Step 'T3  Backend API (port 3000)'
Start-Window 'T3 - Backend' (Join-Path $root 'backend') 'npm start' (Join-Path $logs 't3-backend.log')
Wait-Port 3000 60 'Backend' | Out-Null

# ---------------------------------------------------------------- T4 ML
if (-not $NoMl) {
  Step 'T4  ML anomaly service (port 8000)'
  Start-Window 'T4 - ML service' (Join-Path $root 'ml') '.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8000' (Join-Path $logs 't4-ml.log')
  Wait-Port 8000 60 'ML service' | Out-Null
}

# ---------------------------------------------------------------- T2 deploy + seed
if (-not $NoReset) {
  Step 'T2  Deploy contract + seed demo data (npm run reset-demo)'
  $resetLog = Join-Path $logs 't2-reset-demo.log'
  if (Test-Path $resetLog) { Remove-Item $resetLog -Force }
  Start-Window 'T2 - Deploy + seed' $root 'npm run reset-demo' $resetLog
  $deadline = (Get-Date).AddSeconds(240)
  $result = $null
  while ((Get-Date) -lt $deadline -and -not $result) {
    Start-Sleep -Seconds 2
    if (Test-Path $resetLog) {
      $text = Get-Content $resetLog -Raw -ErrorAction SilentlyContinue
      if ($text -match 'Done in') { $result = 'ok' } elseif ($text -match 'reset-demo failed|npm ERR|ERR!') { $result = 'failed' }
    }
  }
  if ($result -eq 'ok') { Ok 'contract deployed, demo accounts + products seeded, QR images in demo\qr\' }
  elseif ($result -eq 'failed') { throw 'reset-demo failed - see the T2 window or logs\t2-reset-demo.log' }
  else { Warn 'reset-demo is still running - check the T2 window' }
}

# ---------------------------------------------------------------- T5 app
if (-not $NoApp) {
  Step 'T5  Flutter app on the phone'
  if (-not $DeviceId) {
    $line = (& $adb devices) | Where-Object { $_ -match '^(\S+)\s+device$' } | Select-Object -First 1
    if ($line -match '^(\S+)\s+device$') { $DeviceId = $Matches[1] }
  }
  if (-not $DeviceId) {
    Warn 'No Android device found (adb devices). Connect the phone with USB debugging on, then run this script with -NoReset.'
  } else {
    if ($Wifi) {
      $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4Address.IPAddress
      $apiUrl = "http://${ip}:3000"
      Ok "Wi-Fi mode: the app will call $apiUrl (phone and laptop must share the Wi-Fi; firewall must allow port 3000)"
    } else {
      & $adb -s $DeviceId reverse tcp:3000 tcp:3000 | Out-Null
      $apiUrl = 'http://127.0.0.1:3000'
      Ok "USB mode: adb reverse tcp:3000 -> phone uses $apiUrl (keep the cable connected)"
    }
    Start-Window 'T5 - Flutter app' (Join-Path $root 'mobile') "flutter run -d $DeviceId --dart-define=API_BASE_URL=$apiUrl" (Join-Path $logs 't5-flutter.log')
    Ok "building and installing on $DeviceId (first build takes a few minutes; press r / R / q in the T5 window)"
  }
}

# ---------------------------------------------------------------- extras
Start-Process explorer.exe (Join-Path $root 'demo\qr')
Step 'All started'
Write-Host '   Health:     http://localhost:3000/health'
Write-Host '   Demo QRs:   demo\qr\ (opened in Explorer) - expected results in demo\qr\README.md'
Write-Host '   Accounts:   admin@ / maker@ / supplier1@ / retailer1@veritrace.demo  - password Demo@1234'
Write-Host '   Logs:       logs\t1-hardhat.log ... logs\t5-flutter.log'
Write-Host '   Stop:       close the windows (Ctrl+C), or re-run with -Restart'
