# PowerShell (Admin)
$pw = Read-Host "Password para stashuser" -AsSecureString
New-LocalUser -Name "stashuser" -Password $pw -AccountNeverExpires:$true
New-Item -ItemType Directory -Path "E:\stash" -Force | Out-Null
New-SmbShare -Name "stash" -Path "E:\stash" -CachingMode None -FolderEnumerationMode AccessBased -FullAccess "stashuser"
