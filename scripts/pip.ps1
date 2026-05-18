$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonExe = Join-Path $ScriptDir "..\python\python.exe"

if (-Not (Test-Path $PythonExe))
{
    Write-Host "[ERROR] Shared portable Python not found at: $PythonExe" -ForegroundColor Red
    Exit
}

# Strict isolation from the host machine's python environment
$env:PYTHONNOUSERSITE = "1"
$env:PIP_CACHE_DIR = Join-Path $ScriptDir "..\python\.pip_cache"

Write-Host ">>> Executing Portable Pip..." -ForegroundColor Cyan

& $PythonExe -m pip $args
