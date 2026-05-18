$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$PythonDir = Join-Path $WorkspaceDir "python"
$ScriptsDir = Join-Path $PythonDir "Scripts"

if (-Not (Test-Path $PythonDir))
{
  Write-Host "[ERROR] Portable Python not found at: $PythonDir" -ForegroundColor Red
  return
}

if (-Not (Test-Path Env:\_OLD_VIRTUAL_PATH))
{
  $global:_OLD_VIRTUAL_PATH = $env:PATH
}

$env:PYTHONNOUSERSITE = "1"
$env:VIRTUAL_ENV = $WorkspaceDir
$env:PATH = "$PythonDir;$ScriptsDir;" + $env:PATH

# Auto-detect and register Tcl/Tk if the tcl folder exists
$TclDir = Join-Path $PythonDir "tcl"
if (Test-Path $TclDir) {
    # It dynamically finds the tcl8.x and tk8.x folders so it's version-agnostic
    $TclLib = (Get-ChildItem -Path $TclDir -Filter "tcl8.*")[0].FullName
    $TkLib = (Get-ChildItem -Path $TclDir -Filter "tk8.*")[0].FullName
    $env:TCL_LIBRARY = $TclLib
    $env:TK_LIBRARY = $TkLib
}

function global:deactivate
{
  if (Test-Path Env:\_OLD_VIRTUAL_PATH)
  {
    $env:PATH = $env:_OLD_VIRTUAL_PATH
    Remove-Item Env:\_OLD_VIRTUAL_PATH
  }
  Remove-Item Env:\PYTHONNOUSERSITE -ErrorAction SilentlyContinue
  Remove-Item Env:\VIRTUAL_ENV -ErrorAction SilentlyContinue
  Write-Host ">>> Portable environment deactivated." -ForegroundColor Yellow
  Remove-Item function:\deactivate -ErrorAction SilentlyContinue
}

Write-Host ">>> Portable environment activated." -ForegroundColor Green
