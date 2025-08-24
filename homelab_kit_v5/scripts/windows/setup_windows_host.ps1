# setup_windows_host.ps1 - ASCII only
param([string]$ConfigPath = "..\..\config\homelab.env")
. "$PSScriptRoot\lib\Common.ps1"
$ErrorActionPreference = "Stop"
Check-Admin
$cfg = Load-EnvFile -Path $ConfigPath
$ROOT   = Must $cfg "HOST_ROOT_PATH"
$SW     = Must $cfg "SWITCH_PRIVATE_NAME"
$EDGEIP = Must $cfg "EDGE_IP"
$log = Start-Log -Root $ROOT -ScriptName "setup_windows_host"
Write-Log -Message "Start" -LogPath $log
Ensure-Feature -Name "Microsoft-Hyper-V"
Ensure-Feature -Name "Microsoft-Hyper-V-Management-PowerShell"
Ensure-Dir -Path $ROOT
Ensure-Dir -Path (Join-Path $ROOT "vms")
Ensure-Dir -Path (Join-Path $ROOT "shared")
Ensure-Dir -Path (Join-Path $ROOT "logs")
$ifName = "vEthernet ($SW)"
$sw = Get-VMSwitch -Name $SW -ErrorAction SilentlyContinue
if(-not $sw){ Write-Log -Message ("Switch missing: {0}" -f $SW) -LogPath $log }
foreach($p in @(80,443)){
  $exists = (netsh interface portproxy show v4tov4 | Select-String ("0.0.0.0:{0}\s+{1}\s+{0}" -f $p, $EDGEIP))
  if(!$exists){
    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$p connectaddress=$EDGEIP connectport=$p | Out-Null
    Write-Log -Message ("portproxy added: {0} -> {1}" -f $p,$EDGEIP) -LogPath $log
  } else {
    Write-Log -Message ("portproxy ok: {0} -> {1}" -f $p,$EDGEIP) -LogPath $log
  }
  if(-not (Get-NetFirewallRule -DisplayName ("Allow TCP {0} (portproxy)" -f $p) -ErrorAction SilentlyContinue)){
    New-NetFirewallRule -DisplayName ("Allow TCP {0} (portproxy)" -f $p) -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    Write-Log -Message ("firewall rule added: TCP {0}" -f $p) -LogPath $log
  }
}
Snapshot-State -LogPath $log
Write-Log -Message "Done" -LogPath $log
Write-Host ("OK. Log: {0}" -f $log)
