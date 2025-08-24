# DumpText.ps1 - ASCII only
function Convert-ToWindowsPath { param([Parameter(Mandatory)][string]$InputPath)
  if ($InputPath -match '^[A-Za-z]:\\' -or $InputPath -like '\\\\*') { return $InputPath }
  if ($InputPath.StartsWith('/')) {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) { try { $converted = & wsl.exe wslpath -w "$InputPath" 2>$null; if ($LASTEXITCODE -eq 0 -and $converted) { return $converted.Trim() } } catch { } }
    if ($InputPath -match '^/mnt/([a-zA-Z])/(.*)$') { $drive = $Matches[1].ToUpper(); $rest = ($Matches[2] -replace '/', '\\'); return ("{0}:\{1}" -f $drive, $rest) }
    throw "Cannot convert WSL path: $InputPath"
  }
  return $InputPath
}
function Test-IsTextFile { param([Parameter(Mandatory)][string]$Path,[int]$SampleBytes=4096,[double]$MaxNonPrintableRatio=0.20)
  try { $fs=[System.IO.File]::Open($Path,'Open','Read','ReadWrite'); try { $len=[Math]::Min($SampleBytes,$fs.Length); $buf=New-Object byte[] $len; [void]$fs.Read($buf,0,$len); if ($buf -contains 0) { return $false }
    $non=0; foreach($b in $buf){ if(($b -lt 9) -or ($b -gt 13 -and $b -lt 32) -or ($b -ge 127 -and $b -le 159)){ $non++ } }
    if ($len -eq 0) { return $true }; return (($non/[double]$len) -le $MaxNonPrintableRatio)
  } finally { $fs.Close() } } catch { return $false }
}
function Get-TextEncodingFromBom { param([byte[]]$Bytes)
  if ($Bytes.Length -ge 3 -and $Bytes[0]-eq0xEF -and $Bytes[1]-eq0xBB -and $Bytes[2]-eq0xBF) { return 'utf-8' }
  if ($Bytes.Length -ge 2 -and $Bytes[0]-eq0xFF -and $Bytes[1]-eq0xFE) { return 'utf-16' }
  if ($Bytes.Length -ge 2 -and $Bytes[0]-eq0xFE -and $Bytes[1]-eq0xFF) { return 'bigendianunicode' }
  if ($Bytes.Length -ge 4 -and $Bytes[0]-eq0x00 -and $Bytes[1]-eq0x00 -and $Bytes[2]-eq0xFE -and $Bytes[3]-eq0xFF) { return 'utf-32' }
  if ($Bytes.Length -ge 4 -and $Bytes[0]-eq0xFF -and $Bytes[1]-eq0xFE -and $Bytes[2]-eq0x00 -and $Bytes[3]-eq0x00) { return 'utf-32' }
  $null
}
function Read-TextFileSafe { param([string]$Path)
  try { $pre=[System.IO.File]::Open($Path,'Open','Read','ReadWrite'); try { $probeLen=[Math]::Min(4096,$pre.Length); $probe=New-Object byte[] $probeLen; [void]$pre.Read($probe,0,$probeLen); $encName=Get-TextEncodingFromBom -Bytes $probe } finally { $pre.Close() }
    if (-not $encName) { $encName='utf-8' }; $enc=[System.Text.Encoding]::GetEncoding($encName); return [System.IO.File]::ReadAllText($Path,$enc)
  } catch { return $null }
}
$inputPath = Read-Host "Enter root path (Windows or WSL)"
try { $root = Convert-ToWindowsPath -InputPath $inputPath } catch { Write-Error $_.Exception.Message; exit 1 }
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Write-Error "Path does not exist or is not a directory: $root"; exit 1 }
$sizeInput = Read-Host "Per-text-file size limit in MB (Enter = no limit)"
[int64]$maxBytes = 0; if ($sizeInput -match '^\s*\d+\s*$') { $maxBytes = [int64]$sizeInput * 1MB }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"; $outFile = Join-Path -Path $root -ChildPath ("dump_text_{0}.txt" -f $stamp)
"=== TEXT DUMP (recursive) ===" | Out-File -FilePath $outFile -Encoding UTF8
"Input: $inputPath"              | Out-File $outFile -Append -Encoding UTF8
"Root:  $root"                   | Out-File $outFile -Append -Encoding UTF8
"Date:  $(Get-Date -Format s)"   | Out-File $outFile -Append -Encoding UTF8
"---------------------------------------------------------------" | Out-File $outFile -Append -Encoding UTF8
"## Structure (folders and files)" | Out-File $outFile -Append -Encoding UTF8
"### Folders:" | Out-File $outFile -Append -Encoding UTF8
Get-ChildItem -LiteralPath $root -Recurse -Force -Directory | ForEach-Object { $rel = $_.FullName.Substring($root.Length).TrimStart('\\','/'); "- $rel" | Out-File $outFile -Append -Encoding UTF8 }
"`n### Files:" | Out-File $outFile -Append -Encoding UTF8
Get-ChildItem -LiteralPath $root -Recurse -Force -File | ForEach-Object { $rel = $_.FullName.Substring($root.Length).TrimStart('\\','/'); "- $rel (`$($_.Length) bytes, mtime: $($_.LastWriteTime.ToString('s'))) " | Out-File $outFile -Append -Encoding UTF8 }
"---------------------------------------------------------------" | Out-File $outFile -Append -Encoding UTF8
"`n## Text file contents" | Out-File $outFile -Append -Encoding UTF8
$files = Get-ChildItem -LiteralPath $root -Recurse -Force -File
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length).TrimStart('\\','/')
  if (-not (Test-IsTextFile -Path $f.FullName)) { "### $rel`n(Skipped: looks binary)" | Out-File $outFile -Append -Encoding UTF8; continue }
  if ($maxBytes -gt 0 -and $f.Length -gt $maxBytes) { "### $rel`n(Skipped: size $($f.Length) > limit $maxBytes)" | Out-File $outFile -Append -Encoding UTF8; continue }
  $content = Read-TextFileSafe -Path $f.FullName
  if ($null -eq $content) { "### $rel`n(Skipped: read error)" | Out-File $outFile -Append -Encoding UTF8; continue }
  "### $rel" | Out-File $outFile -Append -Encoding UTF8
  "---BEGIN---" | Out-File $outFile -Append -Encoding UTF8
  $content      | Out-File $outFile -Append -Encoding UTF8
  "---END---"   | Out-File $outFile -Append -Encoding UTF8
  ""            | Out-File $outFile -Append -Encoding UTF8
}
"`nDone. Output: $outFile" | Write-Host -ForegroundColor Green
