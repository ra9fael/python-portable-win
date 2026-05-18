param (
  [Parameter(Mandatory=$false)]
  [string]$AppDir = $PWD.Path,
  [Parameter(Mandatory=$false)]
  [string]$TargetScript = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonExe = Join-Path $ScriptDir "..\python\python.exe"

if (-Not (Test-Path $PythonExe))
{
  Write-Host "[ERROR] Shared portable Python not found at: $PythonExe" -ForegroundColor Red
  Pause
  Exit
}

if ($TargetScript -ne "")
{
  $FullPath = Join-Path $AppDir $TargetScript
  if (Test-Path $FullPath)
  {
    & $PythonExe $FullPath
    Exit
  } else
  {
    Write-Host "[ERROR] Target script not found: $FullPath" -ForegroundColor Red
    Pause
    Exit
  }
}

$Scripts = Get-ChildItem -Path $AppDir -Filter "*.py"
if ($Scripts.Count -eq 0)
{
  Write-Host "[WARNING] No Python scripts found in: $AppDir" -ForegroundColor Yellow
  Pause
  Exit
}

Write-Host "======================================" -ForegroundColor Cyan
for ($i = 0; $i -lt $Scripts.Count; $i++)
{
  Write-Host "  [$($i + 1)] $($Scripts[$i].Name)"
}
Write-Host "  [q] Quit"
Write-Host "--------------------------------------" -ForegroundColor Cyan

$Choice = Read-Host "Select a script"

if ($Choice -match '^\d+$' -and [int]$Choice -ge 1 -and [int]$Choice -le $Scripts.Count)
{
  $SelectedScript = $Scripts[[int]$Choice - 1].FullName
  & $PythonExe $SelectedScript
} elseif ($Choice -ne 'q' -and $Choice -ne 'Q')
{
  Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
  Pause
}
