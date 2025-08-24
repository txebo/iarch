# hyperv_setup_network.ps1 - ASCII only
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
if([string]::IsNullOrWhiteSpace($SW)){ throw "SWITCH_PRIVATE_NAME is empty. Check config file homelab.env" }
$log = Start-Log -Root $ROOT -ScriptName "hyperv_setup_network"
Write-Log -Message "Start" -LogPath $log
Ensure-Feature -Name "Microsoft-Hyper-V"
Ensure-Feature -Name "Microsoft-Hyper-V-Management-PowerShell"
$sw = Get-VMSwitch -Name $SW -ErrorAction SilentlyContinue
if($sw){
  if($sw.SwitchType -ne "Internal"){ throw "Switch exists but not Internal: $($sw.SwitchType)" }
  Write-Log -Message ("Switch ok: {0}" -f $SW) -LogPath $log
}else{
  New-VMSwitch -Name $SW -SwitchType Internal | Out-Null
  Write-Log -Message ("Switch created: {0}" -f $SW) -LogPath $log
}
$ifName = "vEthernet ($SW)"
$ifa = Get-NetAdapter -Name $ifName -ErrorAction SilentlyContinue
if(-not $ifa){ throw "Interface not found: $ifName . Reboot and rerun if just created." }
$prefix = Get-PrefixLengthFromCIDR -CIDR $CIDR
Remove-AllIPv4 -IfAlias $ifName
New-NetIPAddress -InterfaceAlias $ifName -IPAddress $HOSTIP -PrefixLength $prefix | Out-Null
Write-Log -Message ("Host IP set: {0}/{1} on {2}" -f $HOSTIP,$prefix,$ifName) -LogPath $log
$nat = Get-NetNat -Name $NAT -ErrorAction SilentlyContinue
if($nat){
  if($nat.InternalIPInterfaceAddressPrefix -ne $CIDR){
    Remove-NetNat -Name $NAT -Confirm:$false | Out-Null
    New-NetNat -Name $NAT -InternalIPInterfaceAddressPrefix $CIDR | Out-Null
    Write-Log -Message ("NAT replaced: {0}" -f $NAT) -LogPath $log
  }else{
    Write-Log -Message ("NAT ok: {0}" -f $NAT) -LogPath $log
  }
}else{
  New-NetNat -Name $NAT -InternalIPInterfaceAddressPrefix $CIDR | Out-Null
  Write-Log -Message ("NAT created: {0}" -f $NAT) -LogPath $log
}
try{ Set-DnsClientServerAddress -InterfaceAlias $ifName -ServerAddresses $EDGEIP; Write-Log -Message ("DNS set to edge: {0}" -f $EDGEIP) -LogPath $log }catch{ Write-Log -Message ("DNS set failed: {0}" -f $_.Exception.Message) -LogPath $log }
function Ensure-VMNic { param([string]$VM,[string]$NicName,[string]$Mac)
  $exists = Get-VM -Name $VM -ErrorAction SilentlyContinue
  if(-not $exists){ Write-Log -Message ("VM not found, skipping nic: {0}" -f $VM) -LogPath $log; return }
  $nic = Get-VMNetworkAdapter -VMName $VM -Name $NicName -ErrorAction SilentlyContinue
  if($nic){ if($nic.SwitchName -ne $SW){ Connect-VMNetworkAdapter -VMName $VM -Name $NicName -SwitchName $SW } }
  else{ Add-VMNetworkAdapter -VMName $VM -Name $NicName -SwitchName $SW | Out-Null }
  Set-VMNetworkAdapter -VMName $VM -Name $NicName -StaticMacAddress $Mac | Out-Null
  Write-Log -Message ("NIC ensured: {0}:{1} mac {2}" -f $VM,$NicName,$Mac) -LogPath $log
}
Ensure-VMNic -VM $EDGEVM -NicName "lan0" -Mac $EDGEMAC
Ensure-VMNic -VM $BKEVM  -NicName "lan0" -Mac $BKEMAC
Snapshot-State -LogPath $log
Write-Log -Message "Done" -LogPath $log
Write-Host ("OK. Log: {0}" -f $log)
