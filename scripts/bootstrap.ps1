param (
  [string]$Version = "",
  [string]$Arch = "amd64",
  [ValidateSet("auto", "embeddable", "pbs")]
  [string]$Engine = "auto",
  [switch]$WithLauncher,
  # Base URL for engine downloads. PBS receives it as --mirror; the embeddable
  # URL becomes <Mirror>/<Version>/python-<Version>-embed-<Arch>.zip.
  [string]$Mirror = "",
  # Optional package index, exported as PIP_INDEX_URL/UV_INDEX_URL for installs.
  [string]$PipIndexUrl = "",
  # Override the pinned hashes from scripts/checksums.psd1.
  [string]$PythonSha256 = "",
  [string]$GetPipSha256 = "",
  [switch]$SkipChecksum,
  [switch]$NonInteractive,
  # Consumer mode: build python/ inside this workspace instead of scripts/..
  [string]$Workspace = "",
  # Optional checksum table; defaults to scripts/checksums.psd1.
  [string]$ChecksumFile = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
$PythonDir = Join-Path $WorkspaceDir "python"
$PythonExe = Join-Path $PythonDir "python.exe"
$PipScript = Join-Path $ScriptDir "pip.ps1"
$ReqFile = Join-Path $WorkspaceDir "requirements.txt"
$LockFile = Join-Path $WorkspaceDir "requirements.lock"
$VersionFile = Join-Path $PythonDir ".portable_version"
$ZipFile = Join-Path $WorkspaceDir "python_embed.zip"
$LauncherScript = Join-Path $ScriptDir "build_launcher.ps1"
$StagingDir = Join-Path $WorkspaceDir "python.new"
$BackupDir = Join-Path $WorkspaceDir "python.old"

. (Join-Path $ScriptDir "checksum.ps1")
$ChecksumTable = if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
  Join-Path $ScriptDir "checksums.psd1"
} else {
  (Resolve-Path -LiteralPath $ChecksumFile).Path
}
$KnownHashes = if (Test-Path $ChecksumTable) { Import-PowerShellDataFile $ChecksumTable } else { @{} }
$RuntimeScripts = Initialize-PortableRuntime -WorkspaceDir $WorkspaceDir -ScriptDir $ScriptDir

if (-Not [string]::IsNullOrWhiteSpace($PipIndexUrl))
{
  $env:PIP_INDEX_URL = $PipIndexUrl
  if (-Not $env:UV_INDEX_URL)
  { $env:UV_INDEX_URL = $PipIndexUrl
  }
}

# Reuse the last successfully installed patch version unless -Version is given.
if ([string]::IsNullOrWhiteSpace($Version))
{
  if (Test-Path $VersionFile)
  {
    $Version = (Get-Content $VersionFile -Raw).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($Version))
  {
    $Version = "3.14.7"
  }
}

function Test-PortablePath
{
  param([string]$Path)

  if ($Path.Length -gt 150)
  {
    Write-Host "[WARN] Package path is $($Path.Length) characters long; keep it under ~120 to avoid MAX_PATH issues." -ForegroundColor Yellow
  }
  if ($Path -match "[^\x00-\x7F]")
  {
    Write-Host "[WARN] Package path contains non-ASCII characters; some build tools handle these poorly." -ForegroundColor Yellow
  }
  if ($Path -match " ")
  {
    Write-Host "[WARN] Package path contains spaces; supported, but a few tools still quote paths incorrectly." -ForegroundColor Yellow
  }
}

function Restore-PreviousEngine
{
  if (Test-Path $PythonDir)
  {
    Remove-Item $PythonDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $BackupDir)
  {
    Rename-Item -Path $BackupDir -NewName (Split-Path $PythonDir -Leaf)
    Write-Host "[OK] Restored the previous environment." -ForegroundColor Green
  }
}

Test-PortablePath $WorkspaceDir

function Install-PbsEngine
{
  param([string]$Version, [string]$Target, [string]$Mirror)

  $TmpDir = Join-Path $WorkspaceDir "python_pbs_tmp"
  if (Test-Path $TmpDir)
  { Remove-Item $TmpDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $TmpDir | Out-Null

  Write-Host "[INFO] Installing CPython $Version via uv (python-build-standalone)..." -ForegroundColor Cyan
  $UvArgs = @("python", "install", $Version, "--install-dir", $TmpDir, "--no-bin", "--no-registry")
  if (-Not [string]::IsNullOrWhiteSpace($Mirror))
  {
    $UvArgs += @("--mirror", $Mirror)
  }
  & uv @UvArgs
  if ($LASTEXITCODE -ne 0)
  {
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    throw "uv python install failed with exit code $LASTEXITCODE"
  }

  $Source = Get-ChildItem -Path $TmpDir -Directory |
    Where-Object { $_.Name -like "cpython-$Version-windows-*" } |
    Select-Object -First 1
  if (-Not $Source)
  {
    $Source = Get-ChildItem -Path $TmpDir -Directory | Select-Object -First 1
  }
  if (-Not $Source)
  {
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    throw "uv did not produce a Python installation."
  }

  Get-ChildItem -Path $Source.FullName -Force |
    Copy-Item -Destination $Target -Recurse -Force
  Remove-Item $TmpDir -Recurse -Force

  # PBS builds are marked as externally managed (PEP 668). This package owns
  # the interpreter and its site-packages, so the marker must go.
  $Markers = @(
    (Join-Path $Target "Lib\EXTERNALLY-MANAGED"),
    (Join-Path $Target "Lib\site-packages\EXTERNALLY-MANAGED")
  )
  foreach ($Marker in $Markers)
  {
    if (Test-Path $Marker)
    {
      Remove-Item $Marker -Force
      Write-Host "[OK] Removed PEP 668 marker: $Marker" -ForegroundColor Green
    }
  }
}

function Wait-ForExit
{
  if ($NonInteractive -or $env:CI)
  { return
  }
  if (-Not [Console]::IsInputRedirected)
  { Read-Host "Press Enter to exit" | Out-Null
  }
}

function Test-UvAvailable
{
  return [bool](Get-Command uv -ErrorAction SilentlyContinue)
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "    Portable Environment Bootstrapper    " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# Phase 1: Environment Backup & Cleanup
# ---------------------------------------------------------
Write-Host "`n[Phase 1/6] Backup Python ..." -ForegroundColor Yellow
if (Test-Path $PythonDir)
{
  Write-Host "`n[WARNING] Existing Python environment detected." -ForegroundColor Yellow
  $CanExport = Test-Path $PythonExe
  $BackupChoice = "N"
  if ($CanExport)
  {
    if (-not $NonInteractive -and -not $env:CI)
    {
      $BackupChoice = Read-Host "Do you want to export current packages to requirements.txt before upgrading? (Y/N)"
    }
    else
    {
      Write-Host "[INFO] Non-interactive mode: skipping package export." -ForegroundColor DarkGray
    }
  }
  else
  {
    Write-Host "[WARNING] $PythonExe not found. The existing environment is incomplete; skipping package export." -ForegroundColor Yellow
  }

  if ($BackupChoice -match "^[yY]")
  {
    Write-Host "[INFO] Exporting dependencies..." -ForegroundColor Cyan
    & $PythonExe -m pip freeze > $ReqFile
    Write-Host "[OK] Dependencies saved to requirements.txt" -ForegroundColor Green
  }
}

# Build the new engine beside the old one and swap only when it is complete,
# so a failed download cannot destroy a working environment.
foreach ($Leftover in @($StagingDir, $BackupDir))
{
  if (Test-Path $Leftover)
  { Remove-Item $Leftover -Recurse -Force -ErrorAction SilentlyContinue
  }
}
New-Item -ItemType Directory -Path $StagingDir | Out-Null

# ---------------------------------------------------------
# Phase 2: Install Engine
# ---------------------------------------------------------
$UsePbs = $false
if ($Engine -eq "pbs" -or $Engine -eq "auto")
{
  if (Test-UvAvailable)
  { $UsePbs = $true
  }
  elseif ($Engine -eq "pbs")
  {
    Write-Host "[ERROR] -Engine pbs requires uv on PATH." -ForegroundColor Red
    Write-Host "        Install uv or use -Engine embeddable." -ForegroundColor Red
    Wait-ForExit
    Exit 1
  }
}

if ($UsePbs)
{
  Write-Host "`n[Phase 2/6] Preparing Python $Version via uv..." -ForegroundColor Yellow
  if ($Arch -ne "amd64")
  {
    Write-Host "[WARNING] uv installs the host architecture; -Arch $Arch is ignored for the PBS engine." -ForegroundColor Yellow
  }

  try
  {
    Install-PbsEngine -Version $Version -Target $StagingDir -Mirror $Mirror
    Write-Host "[OK] python-build-standalone engine installed." -ForegroundColor Green
  }
  catch
  {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        Retry with -Engine embeddable if your network blocks uv's download source." -ForegroundColor Red
    Wait-ForExit
    Exit 1
  }
}
else
{
  Write-Host "`n[Phase 2/6] Downloading Python $Version ($Arch)..." -ForegroundColor Yellow
  if (-Not [string]::IsNullOrWhiteSpace($Mirror))
  {
    $DownloadUrl = "$($Mirror.TrimEnd('/'))/$Version/python-$Version-embed-$Arch.zip"
    Write-Host "[INFO] Using mirror: $DownloadUrl" -ForegroundColor DarkGray
  }
  else
  {
    $DownloadUrl = "https://www.python.org/ftp/python/$Version/python-$Version-embed-$Arch.zip"
  }

  try
  {
    Invoke-WebRequest -Uri $DownloadUrl -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
    Write-Host "[OK] Embeddable package found." -ForegroundColor Green
  }
  catch
  {
    # Some mirrors do not implement HEAD. Try the real download anyway and let
    # that error report the actual status code.
    Write-Host "[WARN] HEAD probe failed; attempting download anyway." -ForegroundColor Yellow
  }

  try
  {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile
    Write-Host "[OK] Download complete." -ForegroundColor Green

    $ExpectedHash = Get-PinnedSha256 -Key "python-$Version-embed-$Arch.zip" -Override $PythonSha256 -Table $KnownHashes
    Assert-Sha256 -Path $ZipFile -Expected $ExpectedHash -Label "python-$Version-embed-$Arch.zip" -Skip:$SkipChecksum
  } catch
  {
    Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        The existing environment was left untouched." -ForegroundColor Red
    Wait-ForExit
    Exit 1
  }

  Write-Host "[INFO] Extracting engine..." -ForegroundColor Cyan
  Expand-Archive -Path $ZipFile -DestinationPath $StagingDir -Force
  Remove-Item -Path $ZipFile -Force
}

# ---------------------------------------------------------
# Swap the staged engine into place
# ---------------------------------------------------------
if (-Not (Test-Path (Join-Path $StagingDir "python.exe")))
{
  Write-Host "[ERROR] The staged engine is incomplete; the existing environment was left untouched." -ForegroundColor Red
  Wait-ForExit
  Exit 1
}

if (Test-Path $PythonDir)
{
  Rename-Item -Path $PythonDir -NewName (Split-Path $BackupDir -Leaf)
  Write-Host "[INFO] Previous environment kept at python.old until bootstrap completes." -ForegroundColor DarkGray
}
Rename-Item -Path $StagingDir -NewName (Split-Path $PythonDir -Leaf)
Write-Host "[OK] New engine swapped in." -ForegroundColor Green

# Pin the exact patch version so a later bare `bootstrap.ps1` reproduces it.
$ActualVersion = $Version
try
{
  $ActualVersion = (& $PythonExe -c "import platform; print(platform.python_version())").Trim()
} catch {}
if (-Not [string]::IsNullOrWhiteSpace($ActualVersion))
{
  Set-Content -Path $VersionFile -Value $ActualVersion -Encoding ASCII
  Write-Host "[OK] Pinned Python version: $ActualVersion" -ForegroundColor Green
}

# ---------------------------------------------------------
# Phase 3: Patch Environment Restrictions (embeddable only)
# ---------------------------------------------------------
if ($UsePbs)
{
  Write-Host "`n[Phase 3/6] Skipping ._pth patch (PBS ships a complete environment)." -ForegroundColor DarkGray
}
else
{
  Write-Host "`n[Phase 3/6] Patching ._pth for site-packages..." -ForegroundColor Yellow

  $PthFile = (Get-ChildItem -Path $PythonDir -Filter "*._pth")[0].FullName
  $Content = Get-Content $PthFile
  $Patched = $false

  for ($i = 0; $i -lt $Content.Count; $i++)
  {
    if ($Content[$i] -match "^#\s*import site")
    {
      $Content[$i] = "import site"
      $Patched = $true
    }
  }

  if ($Patched)
  { Set-Content -Path $PthFile -Value $Content
  }
  Write-Host "[OK] Enabled 'import site'." -ForegroundColor Green
}

# ---------------------------------------------------------
# Phase 4: Install Package Manager
# ---------------------------------------------------------
Write-Host "`n[Phase 4/6] Preparing package manager (pip)..." -ForegroundColor Yellow

& $PythonExe -m pip --version *> $null
if ($LASTEXITCODE -ne 0)
{
  $GetPipUrl = "https://bootstrap.pypa.io/get-pip.py"
  $GetPipFile = Join-Path $PythonDir "get-pip.py"
  try
  {
    Invoke-WebRequest -Uri $GetPipUrl -OutFile $GetPipFile

    $ExpectedHash = Get-PinnedSha256 -Key "get-pip.py" -Override $GetPipSha256 -Table $KnownHashes
    Assert-Sha256 -Path $GetPipFile -Expected $ExpectedHash -Label "get-pip.py" -Skip:$SkipChecksum

    & $PythonExe $GetPipFile --no-warn-script-location
    if ($LASTEXITCODE -ne 0)
    {
      throw "get-pip.py failed with exit code $LASTEXITCODE"
    }
  }
  catch
  {
    Remove-Item $GetPipFile -Force -ErrorAction SilentlyContinue
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Restore-PreviousEngine
    Wait-ForExit
    Exit 1
  }
  Remove-Item $GetPipFile -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] pip is available." -ForegroundColor Green

Write-Host "[INFO] Installing setuptools and wheel (required for sdist builds)..." -ForegroundColor Cyan
& $PythonExe -m pip install --no-warn-script-location setuptools wheel
if ($LASTEXITCODE -ne 0)
{
  Write-Host "[WARN] Retrying with --break-system-packages..." -ForegroundColor Yellow
  & $PythonExe -m pip install --no-warn-script-location --break-system-packages setuptools wheel
  if ($LASTEXITCODE -ne 0)
  {
    throw "Failed to install setuptools and wheel."
  }
}
Write-Host "[OK] setuptools and wheel installed." -ForegroundColor Green

if (-Not $UsePbs)
{
  if (-Not (Test-Path (Join-Path $PythonDir "tcl")))
  {
    Write-Host "[INFO] The embeddable engine has no Tcl/Tk. Run .\scripts\add_tkinter.ps1 if you need tkinter." -ForegroundColor DarkGray
  }
}

# ---------------------------------------------------------
# Phase 5: Dependency Restoration
# ---------------------------------------------------------
Write-Host "`n[Phase 5/6] Dependency Restoring..." -ForegroundColor Yellow

# A lock file is authoritative when present; requirements.txt remains the
# human-edited fallback for projects that do not use locks.
$RestoreFile = $null
if (Test-Path $LockFile)
{ $RestoreFile = $LockFile
}
elseif (Test-Path $ReqFile)
{ $RestoreFile = $ReqFile
}

if ($RestoreFile)
{
  Write-Host "`n[INFO] Found $(Split-Path $RestoreFile -Leaf) in workspace." -ForegroundColor Cyan
  $RestoreChoice = "N"
  if (-not $NonInteractive -and -not $env:CI)
  {
    $RestoreChoice = Read-Host "Do you want to reinstall these packages now? (Y/N)"
  }
  else
  {
    Write-Host "[INFO] Non-interactive mode: skipping dependency restore." -ForegroundColor DarkGray
  }

  if ($RestoreChoice -match "^[yY]")
  {
    Write-Host "[INFO] Restoring packages from $(Split-Path $RestoreFile -Leaf)..." -ForegroundColor Cyan
    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $PipScript -Workspace $WorkspaceDir install -r $RestoreFile
  }
}

# ---------------------------------------------------------
# Phase 6: Startup hook (and the optional example launcher)
# ---------------------------------------------------------
Write-Host "`n[Phase 6/6] Installing startup hook..." -ForegroundColor Yellow

# Readable defaults for tools that invoke pip without inheriting our shell.
# No absolute paths here: caches come from PIP_CACHE_DIR at runtime.
$PipIni = Join-Path $PythonDir "pip.ini"
@"
[global]
user = false
disable-pip-version-check = true
"@ | Set-Content -Path $PipIni -Encoding ASCII
Write-Host "[OK] pip.ini written to python\pip.ini" -ForegroundColor Green

$HookSource = Join-Path $RuntimeScripts "sitecustomize.py"
if (Test-Path $HookSource)
{
  $SitePackages = Join-Path $PythonDir "Lib\site-packages"
  if (-Not (Test-Path $SitePackages))
  {
    New-Item -ItemType Directory -Path $SitePackages -Force | Out-Null
  }
  Copy-Item $HookSource (Join-Path $SitePackages "sitecustomize.py") -Force
  Write-Host "[OK] sitecustomize.py installed (launchers repair themselves after a move)." -ForegroundColor Green
}

Write-Host "[INFO] Building console-script shim (repair payload)..." -ForegroundColor Cyan
if ($WithLauncher)
{
  & $LauncherScript -Workspace $WorkspaceDir
}
else
{
  & $LauncherScript -ShimOnly -Workspace $WorkspaceDir
}
if ($LASTEXITCODE -ne 0)
{
  Write-Host "[ERROR] Shim build failed." -ForegroundColor Red
  Wait-ForExit
  Exit 1
}

if (Test-Path $BackupDir)
{
  Remove-Item $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "[OK] Removed the previous environment (python.old)." -ForegroundColor Green
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host " Bootstrap Complete! Activate and develop. " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  . .\scripts\activate.ps1" -ForegroundColor DarkGray
Write-Host "  python -m pip --version" -ForegroundColor DarkGray
Wait-ForExit
