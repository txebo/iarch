# preflight.ps1 - ASCII only
param([string]$ConfigPath = "..\..\config\homelab.env")
. "$PSScriptRoot\lib\Common.ps1"
$ErrorActionPreference = "Stop"
Check-Admin
$cfg = Load-EnvFile -Path $ConfigPath
$ROOT   = Must $cfg "HOST_ROOT_PATH"
$SW     = Must $cfg "SWITCH_PRIVATE_NAME"
$NAT    = Must $cfg "NAT_NAME"
$CIDR   = Must $cfg "SUBNET_CIDR"
$HOSTIP = Must $cfg "HOST_IP"
$EDGEIP = Must $cfg "EDGE_IP"
$EDGEVM = Must $cfg "EDGE_VM_NAME"
$BKEVM  = Must $cfg "BKEND_VM_NAME"
$EDGEMAC= Must $cfg "EDGE_LAN_MAC"
$BKEMAC = Must $cfg "BKEND_LAN_MAC"
$log = Start-Log -Root $ROOT -ScriptName "preflight"
Write-Log -Message "Preflight start" -LogPath $log
Snapshot-State -LogPath $log
Ensure-Dir -Path $ROOT
Ensure-Dir -Path (Join-Path $ROOT "vms")
Ensure-Dir -Path (Join-Path $ROOT "shared")
Ensure-Dir -Path (Join-Path $ROOT "logs")
Write-Log -Message ("Root ensured at {0}" -f $ROOT) -LogPath $log
Ensure-Feature -Name "Microsoft-Hyper-V"
Ensure-Feature -Name "Microsoft-Hyper-V-Management-PowerShell"
Write-Log -Message "Hyper-V features ensured" -LogPath $log
$sw = Get-VMSwitch -Name $SW -ErrorAction SilentlyContinue
if($sw){ Write-Log -Message ("Switch present: {0} type {1}" -f $sw.Name, $sw.SwitchType) -LogPath $log }
else { Write-Log -Message ("Switch missing: {0}" -f $SW) -LogPath $log }
foreach($vm in @($EDGEVM,$BKEVM)){
  $v = Get-VM -Name $vm -ErrorAction SilentlyContinue
  if($v){ Write-Log -Message ("VM present: {0} state {1}" -f $vm, $v.State) -LogPath $log }
  else  { Write-Log -Message ("VM missing: {0}" -f $vm) -LogPath $log }
}
netsh interface portproxy show v4tov4 | Tee-Object -FilePath $log -Append | Out-Null
Write-Log -Message "Preflight done" -LogPath $log
Write-Host ("OK. Log: {0}" -f $log)
