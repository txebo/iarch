# kit_selfcheck.ps1 - ASCII only
param([string]$Root = "..\..")
$ErrorActionPreference = "Stop"
$expected = @(
  "config\homelab.env",
  "config\cf_env.env",
  "scripts\windows\lib\Common.ps1",
  "scripts\windows\preflight.ps1",
  "scripts\windows\hyperv_setup_network.ps1",
  "scripts\windows\setup_windows_host.ps1",
  "scripts\windows\verify_state.ps1",
  "scripts\windows\kit_selfcheck.ps1",
  "scripts\windows\host_restorepoint.ps1",
  "scripts\windows\hyperv_checkpoint.ps1",
  "scripts\windows\DumpText.ps1"
)
$missing = @()
foreach($rel in $expected){
  $p = Join-Path $Root $rel
  if(-not (Test-Path -LiteralPath $p)){ $missing += $rel }
}
if($missing.Count -gt 0){
  Write-Host "Missing files:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  exit 2
}else{
  Write-Host "All expected files present." -ForegroundColor Green
  exit 0
}
