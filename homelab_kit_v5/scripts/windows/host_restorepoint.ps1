# host_restorepoint.ps1 - ASCII only
$ErrorActionPreference = "Stop"
try {
  Checkpoint-Computer -Description "homelab_kit_v5" -RestorePointType "MODIFY_SETTINGS"
  Write-Host "Restore point created."
} catch {
  Write-Host "System Restore not available or disabled. Skipping."
}
