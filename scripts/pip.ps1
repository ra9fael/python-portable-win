# pip arguments such as -r must pass through untouched, so -Workspace is parsed
# manually instead of being declared in a param() block (PowerShell would bind
# the first positional argument, e.g. "install", to it).
$Workspace = ""
$PipArgs = @()
$RawArgs = @($args)
for ($i = 0; $i -lt $RawArgs.Count; $i++)
{
    if ($RawArgs[$i] -eq "-Workspace")
    {
        if ($i + 1 -ge $RawArgs.Count) { throw "-Workspace requires a value" }
        $Workspace = $RawArgs[$i + 1]
        $i++
    }
    else
    {
        $PipArgs += $RawArgs[$i]
    }
}
$UsePip = $false
if ($PipArgs -contains "-UsePip")
{
    $UsePip = $true
    $PipArgs = @($PipArgs | Where-Object { $_ -ne "-UsePip" })
}

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
$PythonDir = Join-Path $WorkspaceDir "python"
$PythonExe = Join-Path $PythonDir "python.exe"
$RepairScript = Join-Path $WorkspaceDir "scripts\repair.py"
if (-Not (Test-Path $RepairScript))
{
    $RepairScript = Join-Path $ScriptDir "repair.py"
}
$LockFile = Join-Path $WorkspaceDir "requirements.lock"

if (-Not (Test-Path $PythonExe))
{
    Write-Host "[ERROR] Shared portable Python not found at: $PythonExe" -ForegroundColor Red
    Exit 1
}

# Strict isolation from the host machine's python environment.
$env:PYTHONNOUSERSITE = "1"
$env:PIP_USER = "0"

$SubCommand = if ($PipArgs.Count -gt 0) { [string]$PipArgs[0] } else { "" }

# Never let a direct --user install escape the package.
if (@($PipArgs | Where-Object { $_ -match '^--user(=|$)' }).Count -gt 0)
{
    Write-Host "[ERROR] --user installs are disabled: packages must stay inside the package directory." -ForegroundColor Red
    Write-Host "        Use .\scripts\pip.ps1 install <pkg> without --user." -ForegroundColor Red
    Exit 2
}

# Map pip environment variables onto their uv equivalents so mirrors/offline
# settings work regardless of which installer runs.
if (-Not $env:UV_INDEX_URL -and $env:PIP_INDEX_URL) { $env:UV_INDEX_URL = $env:PIP_INDEX_URL }
if (-Not $env:UV_EXTRA_INDEX_URL -and $env:PIP_EXTRA_INDEX_URL) { $env:UV_EXTRA_INDEX_URL = $env:PIP_EXTRA_INDEX_URL }
if (-Not $env:UV_FIND_LINKS -and $env:PIP_FIND_LINKS) { $env:UV_FIND_LINKS = $env:PIP_FIND_LINKS }
if (-Not $env:UV_NO_INDEX -and $env:PIP_NO_INDEX -and $env:PIP_NO_INDEX -ne "0") { $env:UV_NO_INDEX = "1" }

# Rebuild launchers and restore the startup hook after any install-state change.
# repair.py is idempotent and also runs when the install failed halfway.
function Finish([int]$Code)
{
  if ($SubCommand -in @("install", "sync", "uninstall"))
  {
    & $PythonExe $RepairScript $WorkspaceDir | Out-Null
  }
  exit $Code
}

$Uv = Get-Command uv -ErrorAction SilentlyContinue

# `pip.ps1 lock` produces a hash-pinned lock file from requirements.in,
# requirements.txt, or pyproject.toml, in that order.
if ($SubCommand -eq "lock")
{
    if (-Not $Uv)
    {
        Write-Host "[ERROR] lock requires uv on PATH." -ForegroundColor Red
        Exit 1
    }

    $InputFile = $null
    foreach ($Candidate in @("requirements.in", "requirements.txt", "pyproject.toml"))
    {
        $Path = Join-Path $WorkspaceDir $Candidate
        if (Test-Path $Path)
        {
            $InputFile = $Path
            break
        }
    }
    if (-Not $InputFile)
    {
        Write-Host "[ERROR] No requirements.in, requirements.txt, or pyproject.toml found." -ForegroundColor Red
        Exit 1
    }

    Write-Host ">>> Locking $(Split-Path $InputFile -Leaf) -> requirements.lock ..." -ForegroundColor Cyan
    $PyVersion = (& $PythonExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')").Trim()
    & uv pip compile $InputFile --generate-hashes --no-header --python-version $PyVersion --python-platform windows -o $LockFile
    exit $LASTEXITCODE
}

if ($UsePip -or -Not $Uv)
{
    $env:PIP_CACHE_DIR = Join-Path $PythonDir ".pip_cache"
    Write-Host ">>> Executing Portable Pip..." -ForegroundColor Cyan
    & $PythonExe -m pip @PipArgs
    Finish $LASTEXITCODE
}

# uv only changes how packages are installed; the runtime stays self-contained.
$env:UV_CACHE_DIR = Join-Path $PythonDir ".uv_cache"
Write-Host ">>> Executing Portable uv pip..." -ForegroundColor Cyan

$UvArgs = @("pip") + $PipArgs

if ($SubCommand -ne "compile")
{
    $UvArgs += @("--python", $PythonExe, "--system")

    $Marker = Join-Path $PythonDir "Lib\site-packages\EXTERNALLY-MANAGED"
    if ($SubCommand -in @("install", "sync") -and (Test-Path $Marker))
    {
        $UvArgs += "--break-system-packages"
    }
}

& uv @UvArgs
Finish $LASTEXITCODE
