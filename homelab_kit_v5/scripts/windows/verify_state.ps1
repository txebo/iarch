# verify_state.ps1 - ASCII only
param([string]$ConfigPath = "..\..\config\homelab.env")
. "$PSScriptRoot\lib\Common.ps1"
$ErrorActionPreference = "Stop"
$cfg = Load-EnvFile -Path $ConfigPath
$ROOT   = Must $cfg "HOST_ROOT_PATH"
$SW     = Must $cfg "SWITCH_PRIVATE_NAME"
$EDGEVM = Must $cfg "EDGE_VM_NAME"
$BKEVM  = Must $cfg "BKEND_VM_NAME"
$log = Start-Log -Root $ROOT -ScriptName "verify_state"
Write-Log -Message "Verify start" -LogPath $log
Snapshot-State -LogPath $log
foreach($vm in @($EDGEVM,$BKEVM)){
  $v = Get-VM -Name $vm -ErrorAction SilentlyContinue
  if($v){
    $nics = Get-VMNetworkAdapter -VMName $vm -ErrorAction SilentlyContinue
    foreach($n in $nics){
      Write-Log -Message ("VM {0} NIC {1} Switch {2} MAC {3}" -f $vm,$n.Name,$n.SwitchName,$n.MacAddress) -LogPath $log
    }
  } else {
    Write-Log -Message ("VM missing: {0}" -f $vm) -LogPath $log
  }
}
Write-Log -Message "Verify done" -LogPath $log
Write-Host ("OK. Log: {0}" -f $log)
