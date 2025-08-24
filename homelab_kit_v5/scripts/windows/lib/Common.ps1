# Common.ps1 - ASCII only
$ErrorActionPreference = "Stop"
function Load-EnvFile { param([Parameter(Mandatory)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){ throw "Config file not found: $Path" }
  $vars = @{}
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if($line -eq "" -or $line.StartsWith("#")){ return }
    $kv = $line -split "=",2
    if($kv.Count -ne 2){ throw "Invalid line: $line" }
    $k = $kv[0].Trim(); $v = $kv[1].Trim()
    $vars[$k] = $v
  }
  return $vars
}
function Must { param([hashtable]$H, [string]$K)
  if(-not $H.ContainsKey($K) -or [string]::IsNullOrWhiteSpace($H[$K])){ throw "Missing required var: $K" }
  return $H[$K]
}
function Check-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw "Run as Administrator" }
}
function Start-Log { param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ScriptName)
  $logs = Join-Path $Root "logs"; if(-not (Test-Path -LiteralPath $logs)){ New-Item -ItemType Directory -Path $logs -Force | Out-Null }
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"; $logPath = Join-Path $logs ("{0}_{1}.log" -f $stamp, $ScriptName)
  New-Item -ItemType File -Path $logPath -Force | Out-Null; return $logPath
}
function Write-Log { param([Parameter(Mandatory)][string]$Message,[Parameter(Mandatory)][string]$LogPath)
  $ts = Get-Date -Format "s"; $line = "[{0}] {1}" -f $ts, $Message; $line | Tee-Object -FilePath $LogPath -Append
}
function Get-PrefixLengthFromCIDR { param([Parameter(Mandatory)][string]$CIDR)
  if($CIDR -notmatch "/(\d+)$"){ throw "Invalid SUBNET_CIDR: $CIDR" } return [int]$Matches[1]
}
function Ensure-Feature { param([Parameter(Mandatory)][string]$Name)
  $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
  if(!$f -or $f.State -ne "Enabled"){ Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart | Out-Null }
}
function Ensure-Dir { param([Parameter(Mandatory)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){ New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}
function Remove-AllIPv4 { param([Parameter(Mandatory)][string]$IfAlias)
  $ips = Get-NetIPAddress -InterfaceAlias $IfAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
  foreach($r in $ips){ try{ Remove-NetIPAddress -InterfaceAlias $IfAlias -IPAddress $r.IPAddress -Confirm:$false -ErrorAction SilentlyContinue }catch{} }
}
function Snapshot-State { param([Parameter(Mandatory)][string]$LogPath)
  Write-Log -Message "State snapshot begin" -LogPath $LogPath
  try{ "VMSwitches:" | Tee-Object -FilePath $LogPath -Append; Get-VMSwitch | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $LogPath -Append | Out-Null }catch{}
  try{ "NetNat:" | Tee-Object -FilePath $LogPath -Append; Get-NetNat | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $LogPath -Append | Out-Null }catch{}
  try{ "Portproxy v4tov4:" | Tee-Object -FilePath $LogPath -Append; netsh interface portproxy show v4tov4 | Tee-Object -FilePath $LogPath -Append | Out-Null }catch{}
  try{ "Adapters:" | Tee-Object -FilePath $LogPath -Append; Get-NetAdapter | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $LogPath -Append | Out-Null }catch{}
  Write-Log -Message "State snapshot end" -LogPath $LogPath
}
