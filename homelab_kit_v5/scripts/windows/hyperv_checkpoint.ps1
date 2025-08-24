# hyperv_checkpoint.ps1 - ASCII only
param([Parameter(Mandatory=$true)][string]$VMName,[Parameter(Mandatory=$true)][string]$CheckpointName)
$ErrorActionPreference = "Stop"
if(-not (Get-VM -Name $VMName -ErrorAction SilentlyContinue)){ throw "VM not found: $VMName" }
Checkpoint-VM -Name $VMName -SnapshotName $CheckpointName -Confirm:$false | Out-Null
Write-Host ("Checkpoint created: {0} -> {1}" -f $VMName,$CheckpointName)
