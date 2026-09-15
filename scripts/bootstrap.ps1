param (
  [string]$Version = "3.14.7",
  [string]$Arch = "amd64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = Join-Path $ScriptDir ".."
$PythonDir = Join-Path $WorkspaceDir "python"
$PythonExe = Join-Path $PythonDir "python.exe"
$PipScript = Join-Path $ScriptDir "pip.ps1"
$ReqFile = Join-Path $WorkspaceDir "requirements.txt"
$ZipFile = Join-Path $WorkspaceDir "python_embed.zip"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "    Portable Environment Bootstrapper    " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# Phase 1: Environment Backup & Cleanup
# ---------------------------------------------------------
Write-Host "`n[Phase 1/5] Backup Python ..." -ForegroundColor Yellow
if (Test-Path $PythonDir)
{
  Write-Host "`n[WARNING] Existing Python environment detected." -ForegroundColor Yellow
  $CanExport = Test-Path $PythonExe
  $BackupChoice = "N"
  if ($CanExport)
  {
    $BackupChoice = Read-Host "Do you want to export current packages to requirements.txt before upgrading? (Y/N)"
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

  Write-Host "[INFO] Removing old python directory..." -ForegroundColor DarkGray
  Remove-Item -Path $PythonDir -Recurse -Force
}

New-Item -ItemType Directory -Path $PythonDir | Out-Null

# ---------------------------------------------------------
# Phase 2: Download & Extract Engine
# ---------------------------------------------------------
Write-Host "`n[Phase 2/5] Downloading Python $Version ($Arch)..." -ForegroundColor Yellow
$DownloadUrl = "https://www.python.org/ftp/python/$Version/python-$Version-embed-$Arch.zip"

try
{
  Invoke-WebRequest -Uri $DownloadUrl -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
  Write-Host "[OK] Embeddable package found on python.org." -ForegroundColor Green
}
catch
{
  $Resp = $_.Exception.Response
  $StatusCode = $null
  if ($null -ne $Resp)
  {
    try { $StatusCode = [int]$Resp.StatusCode } catch { $StatusCode = $null }
  }

  if ($StatusCode -eq 404)
  {
    Write-Host "[ERROR] No embeddable package found for Python $Version ($Arch)." -ForegroundColor Red
    Write-Host "        The version string is probably invalid, or this release/arch has no embeddable zip." -ForegroundColor Red
    Write-Host "        Check https://www.python.org/downloads/windows/ for valid versions." -ForegroundColor Red
  }
  else
  {
    Write-Host "[ERROR] Network error: could not reach python.org." -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        Check your network connection, proxy settings, or try again later." -ForegroundColor Red
  }
  Pause
  Exit
}

try
{
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile
  Write-Host "[OK] Download complete." -ForegroundColor Green
} catch
{
  Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
  Pause
  Exit
}

Write-Host "[INFO] Extracting engine..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath $PythonDir -Force
Remove-Item -Path $ZipFile -Force

# ---------------------------------------------------------
# Phase 3: Patch Environment Restrictions
# ---------------------------------------------------------
Write-Host "`n[Phase 3/5] Patching ._pth for site-packages..." -ForegroundColor Yellow

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

# ---------------------------------------------------------
# Phase 4: Install Package Manager (pip)
# ---------------------------------------------------------
Write-Host "`n[Phase 4/5] Installing Package Manager (pip)..." -ForegroundColor Yellow
$GetPipUrl = "https://bootstrap.pypa.io/get-pip.py"
$GetPipFile = Join-Path $PythonDir "get-pip.py"

Invoke-WebRequest -Uri $GetPipUrl -OutFile $GetPipFile
& $PythonExe $GetPipFile --no-warn-script-location
Remove-Item $GetPipFile -Force
Write-Host "[OK] pip installed successfully." -ForegroundColor Green

# ---------------------------------------------------------
# Phase 5: Dependency Restoration
# ---------------------------------------------------------
Write-Host "`n[Phase 5/5] Dependency Restoring..." -ForegroundColor Yellow
if (Test-Path $ReqFile)
{
  Write-Host "`n[INFO] Found requirements.txt in workspace." -ForegroundColor Cyan
  $RestoreChoice = Read-Host "Do you want to reinstall these packages now? (Y/N)"

  if ($RestoreChoice -match "^[yY]")
  {
    Write-Host "[INFO] Restoring packages..." -ForegroundColor Cyan
    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $PipScript install -r $ReqFile
  }
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host " Bootstrap Complete! The system is ready.  " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Pause
