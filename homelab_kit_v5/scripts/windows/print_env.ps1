# print_env.ps1 - ASCII only
param([string]$ConfigPath = "..\..\config\homelab.env")
$ErrorActionPreference = "Stop"
if(-not (Test-Path -LiteralPath $ConfigPath)){ throw "Config file not found: $ConfigPath" }
$lines = Get-Content -LiteralPath $ConfigPath
$vars = @{}
foreach($raw in $lines){
  $line = $raw.Trim()
  if($line -eq "" -or $line.StartsWith("#")){ continue }
  $kv = $line -split "=",2
  if($kv.Count -ne 2){ throw "Invalid line: $line" }
  $k = $kv[0].Trim()
  $v = $kv[1].Trim()
  $vars[$k] = $v
}
$vars.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }
