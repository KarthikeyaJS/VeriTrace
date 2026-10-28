<#
.SYNOPSIS
  Stops everything start-all.ps1 started: blockchain (8545), backend (3000), ML service (8000) and a running
  `flutter run` session. The windows stay open showing "stopped" - close them afterwards.
  Note: stopping the blockchain wipes it; start-all.ps1 re-deploys and re-seeds the demo next time.
#>
$ports = @{ 8545 = 'Hardhat node (blockchain)'; 3000 = 'backend'; 8000 = 'ML service' }
foreach ($port in $ports.Keys) {
  $owners = (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).OwningProcess | Select-Object -Unique
  if ($owners) {
    foreach ($p in $owners) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
    Write-Host "stopped $($ports[$port]) (port $port)" -ForegroundColor Green
  } else {
    Write-Host "$($ports[$port]) was not running" -ForegroundColor DarkGray
  }
}
Get-CimInstance Win32_Process -Filter "Name='dart.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'flutter_tools' -and $_.CommandLine -match '\srun\s' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host 'stopped flutter run' -ForegroundColor Green }
