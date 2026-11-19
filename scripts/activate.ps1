param (
  # Consumer mode: activate python/ inside this workspace (e.g. .portable).
  [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
$PythonDir = Join-Path $WorkspaceDir "python"
$ScriptsDir = Join-Path $PythonDir "Scripts"
$RepairScript = Join-Path $WorkspaceDir "scripts\repair.py"
if (-Not (Test-Path $RepairScript))
{
  $RepairScript = Join-Path $ScriptDir "repair.py"
}

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

# Keep caches and Jupyter metadata inside the package instead of %APPDATA%
$env:JUPYTER_DATA_DIR = Join-Path $PythonDir "share\jupyter"
$env:PIP_CACHE_DIR = Join-Path $PythonDir ".pip_cache"
$env:UV_CACHE_DIR = Join-Path $PythonDir ".uv_cache"

# pip defaults that survive tools which invoke pip.exe directly
$env:PIP_CONFIG_FILE = Join-Path $PythonDir "pip.ini"
$env:PIP_USER = "0"
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

# Optional offline wheelhouse produced by build_release.ps1 -Wheelhouse
$WheelDir = Join-Path $WorkspaceDir "wheels"
if (Test-Path $WheelDir)
{
  if (-Not $env:PIP_FIND_LINKS)
  {
    $env:PIP_FIND_LINKS = $WheelDir
    $global:_PORTABLE_PIP_FIND_LINKS_SET = $true
  }
  if (-Not $env:UV_FIND_LINKS)
  {
    $env:UV_FIND_LINKS = $WheelDir
    $global:_PORTABLE_UV_FIND_LINKS_SET = $true
  }
}

# Mirror settings are expressed with pip variable names; uv uses UV_* names.
if (-Not $env:UV_INDEX_URL -and $env:PIP_INDEX_URL)
{
  $env:UV_INDEX_URL = $env:PIP_INDEX_URL
  $global:_PORTABLE_UV_INDEX_SET = $true
}
if (-Not $env:UV_EXTRA_INDEX_URL -and $env:PIP_EXTRA_INDEX_URL)
{
  $env:UV_EXTRA_INDEX_URL = $env:PIP_EXTRA_INDEX_URL
  $global:_PORTABLE_UV_EXTRA_INDEX_SET = $true
}

# Pin uv to this interpreter so a bare `uv pip install` cannot target the host
$env:UV_SYSTEM_PYTHON = "1"
$env:UV_PYTHON = Join-Path $PythonDir "python.exe"

# Rebuild tool launchers if this copy of the package lives somewhere else now.
$Marker = Join-Path $PythonDir ".portable_root"
$Stale = $true
if (Test-Path $Marker)
{
  $Stale = (Get-Content $Marker -Raw).Trim() -ne $WorkspaceDir
}
if ($Stale)
{
  & (Join-Path $PythonDir "python.exe") $RepairScript $WorkspaceDir
}

# Auto-detect and register Tcl/Tk for the embeddable engine (8.x layout).
# PBS ships Tcl/Tk 9.x and finds its libraries on its own, so nothing is set there.
$TclDir = Join-Path $PythonDir "tcl"
if (Test-Path $TclDir) {
    if (-Not $global:_PORTABLE_TCL_SAVED) {
        $global:_OLD_TCL_LIBRARY = $env:TCL_LIBRARY
        $global:_OLD_TK_LIBRARY = $env:TK_LIBRARY
        $global:_PORTABLE_TCL_SAVED = $true
    }
    $TclLib = Get-ChildItem -Path $TclDir -Filter "tcl8.*" -Directory | Select-Object -First 1
    $TkLib = Get-ChildItem -Path $TclDir -Filter "tk8.*" -Directory | Select-Object -First 1
    if ($TclLib) { $env:TCL_LIBRARY = $TclLib.FullName }
    if ($TkLib) { $env:TK_LIBRARY = $TkLib.FullName }
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
  Remove-Item Env:\JUPYTER_DATA_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\PIP_CACHE_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\UV_CACHE_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\PIP_CONFIG_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:\PIP_USER -ErrorAction SilentlyContinue
  Remove-Item Env:\PIP_DISABLE_PIP_VERSION_CHECK -ErrorAction SilentlyContinue
  if ($global:_PORTABLE_PIP_FIND_LINKS_SET) { Remove-Item Env:\PIP_FIND_LINKS -ErrorAction SilentlyContinue }
  if ($global:_PORTABLE_UV_FIND_LINKS_SET) { Remove-Item Env:\UV_FIND_LINKS -ErrorAction SilentlyContinue }
  if ($global:_PORTABLE_UV_INDEX_SET) { Remove-Item Env:\UV_INDEX_URL -ErrorAction SilentlyContinue }
  if ($global:_PORTABLE_UV_EXTRA_INDEX_SET) { Remove-Item Env:\UV_EXTRA_INDEX_URL -ErrorAction SilentlyContinue }
  if ($global:_PORTABLE_TCL_SAVED)
  {
    if ($null -ne $global:_OLD_TCL_LIBRARY) { $env:TCL_LIBRARY = $global:_OLD_TCL_LIBRARY }
    else { Remove-Item Env:\TCL_LIBRARY -ErrorAction SilentlyContinue }
    if ($null -ne $global:_OLD_TK_LIBRARY) { $env:TK_LIBRARY = $global:_OLD_TK_LIBRARY }
    else { Remove-Item Env:\TK_LIBRARY -ErrorAction SilentlyContinue }
  }
  Remove-Variable _OLD_TCL_LIBRARY -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _OLD_TK_LIBRARY -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _PORTABLE_TCL_SAVED -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _PORTABLE_PIP_FIND_LINKS_SET -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _PORTABLE_UV_FIND_LINKS_SET -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _PORTABLE_UV_INDEX_SET -Scope Global -ErrorAction SilentlyContinue
  Remove-Variable _PORTABLE_UV_EXTRA_INDEX_SET -Scope Global -ErrorAction SilentlyContinue
  Remove-Item Env:\UV_SYSTEM_PYTHON -ErrorAction SilentlyContinue
  Remove-Item Env:\UV_PYTHON -ErrorAction SilentlyContinue
  Write-Host ">>> Portable environment deactivated." -ForegroundColor Yellow
  Remove-Item function:\deactivate -ErrorAction SilentlyContinue
}

Write-Host ">>> Portable environment activated." -ForegroundColor Green
