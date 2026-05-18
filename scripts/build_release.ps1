# scripts/build_release.ps1
# Stages a clean portable distribution: copies only runtime files, replaces
# hardcoded-shebang .exe entry points with generated .bat wrappers, then zips.

param(
    [Parameter(Mandatory=$false)]
    [string]$ReleaseName = "Portable_Python",
    [Parameter(Mandatory=$false)]
    [switch]$AppendDateTime,
    [Parameter(Mandatory=$false)]
    [switch]$KeepStaging
)

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$StagingDir  = Join-Path $WorkspaceDir "_release_staging"

$DistDir = Join-Path $WorkspaceDir "dist"
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Force $DistDir | Out-Null }

if ($AppendDateTime) {
    $TimeStamp = Get-Date -Format "yyyyMMdd_HHmm"
    $ReleaseZip = Join-Path $DistDir "$ReleaseName`_$TimeStamp.zip"
} else {
    $ReleaseZip = Join-Path $DistDir "$ReleaseName.zip"
}

# ---------- helpers ----------

function Write-Step($msg) {
    Write-Host $msg -ForegroundColor Cyan
}

# ---------- cleanup previous ----------

if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
if (Test-Path $ReleaseZip)  { Remove-Item $ReleaseZip -Force }

# ---------- step 1: copy runtime files to staging ----------

Write-Step "[1/5] Copying runtime files to staging..."

$ExcludeTop = @("python", "scripts", "dist", ".git", ".vscode", ".claude", "__pycache__")
$AppDirs = Get-ChildItem $WorkspaceDir -Directory `
  | Where-Object { $_.Name -notin $ExcludeTop -and -not $_.Name.StartsWith(".") }

New-Item -ItemType Directory -Force $StagingDir | Out-Null

# copy python engine
Copy-Item (Join-Path $WorkspaceDir "python") (Join-Path $StagingDir "python") -Recurse

# copy scripts (PowerShell tooling)
Copy-Item (Join-Path $WorkspaceDir "scripts") (Join-Path $StagingDir "scripts") -Recurse

# copy app dirs
foreach ($dir in $AppDirs) {
    $src = Join-Path $WorkspaceDir $dir.Name
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $StagingDir $dir.Name) -Recurse
        Write-Host "  [COPY] $($dir.Name)/"
    }
}

# copy any top-level .bat launchers
Get-ChildItem $WorkspaceDir -Filter "*.bat" -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $StagingDir $_.Name)
    Write-Host "  [COPY] $($_.Name)"
}

# ---------- step 2: generate .bat wrappers, delete .exe ----------

Write-Step "[2/5] Generating .bat wrappers (replacing hardcoded .exe)..."

$StagingScripts  = Join-Path $StagingDir "python\Scripts"
$StagingSitePkgs = Join-Path $StagingDir "python\Lib\site-packages"
$LocalPythonExe  = Join-Path $WorkspaceDir "python\python.exe"

$PyGenScript = @'
import configparser, sys
from pathlib import Path

staging_scripts  = Path(sys.argv[1])
site_packages    = Path(sys.argv[2])

if not staging_scripts.exists():
    print(f"  [ERROR] Scripts dir not found: {staging_scripts}")
    sys.exit(1)

# grab every .exe name (lowercased for matching)
exe_names = {exe.stem: exe for exe in staging_scripts.glob("*.exe")}
if not exe_names:
    print("  [WARN] No .exe files in staging Scripts/ — nothing to wrap")
    sys.exit(0)

# build entry_point map from dist-info metadata
ep_map = {}   # name_lower -> (module, func)
for dist_info in sorted(site_packages.glob("*.dist-info")):
    ep_file = dist_info / "entry_points.txt"
    if not ep_file.exists():
        continue
    cfg = configparser.ConfigParser()
    cfg.read(ep_file, encoding="utf-8")
    for section in ("console_scripts", "gui_scripts"):
        if section not in cfg.sections():
            continue
        for name, value in cfg.items(section):
            raw = value.split("[")[0].strip()
            module, _, attrs = raw.partition(":")
            func = attrs if attrs else "main"
            ep_map[name.strip().lower()] = (module, func)

generated = 0
for stem, exe_path in sorted(exe_names.items()):
    stem_lower = stem.lower()

    if stem_lower in ep_map:
        module, func = ep_map[stem_lower]
    else:
        # fallback: try to strip version suffix, then python -m
        import re
        base = re.sub(r'[\d.]+$', '', stem_lower)
        if base in ep_map:
            module, func = ep_map[base]
        else:
            module, func = stem_lower, None
            print(f"  [WARN] No entry_point for {exe_path.name}, using -m {stem_lower}")

    bat_path = staging_scripts / f"{stem}.bat"

    if func:
        bat_path.write_text(
            f'@echo off\r\n'
            f'set "PYTHONNOUSERSITE=1"\r\n'
            f'"%~dp0..\\python.exe" -c "import sys; from {module} import {func}; sys.exit({func}())" %*\r\n',
            encoding="utf-8"
        )
    else:
        bat_path.write_text(
            f'@echo off\r\n'
            f'set "PYTHONNOUSERSITE=1"\r\n'
            f'"%~dp0..\\python.exe" -m {module} %*\r\n',
            encoding="utf-8"
        )

    print(f"  [OK] {stem}.bat  <-  {module}{':' + func if func else ''}")
    generated += 1

# delete every .exe
for exe_path in exe_names.values():
    exe_path.unlink()
    print(f"  [DEL] {exe_path.name}")

print(f"\n  Generated {generated} wrappers, removed {len(exe_names)} .exe files")
'@

& $LocalPythonExe -c $PyGenScript $StagingScripts $StagingSitePkgs
if ($LASTEXITCODE -ne 0) { throw "Bat-wrapper generation failed (exit $LASTEXITCODE)" }

# ---------- step 3: purge caches ----------

Write-Step "[3/5] Purging caches..."

$PipCache = Join-Path $StagingDir "python\.pip_cache"
if (Test-Path $PipCache) {
    Remove-Item $PipCache -Recurse -Force
    Write-Host "  [DEL] python/.pip_cache"
}

Get-ChildItem $StagingDir -Recurse -Filter "__pycache__" -Directory `
  | Remove-Item -Recurse -Force

Write-Host "  pycache purged"

# ---------- step 4: handle pdf/ (app-specific, if present) ----------

# pdf/ may contain heavy PDF test files — skip *.pdf if the dir exists
$PdfDir = Join-Path $StagingDir "pdf"
if (Test-Path $PdfDir) {
    Write-Step "[4/5] Stripping large assets from pdf/..."
    Get-ChildItem $PdfDir -Filter "*.pdf" -File | Remove-Item -Force
    Get-ChildItem $PdfDir -Recurse -Filter "__pycache__" -Directory | Remove-Item -Recurse -Force
}

# ---------- step 5: zip ----------

Write-Step "[5/5] Creating release archive..."

Compress-Archive -Path "$StagingDir\*" -DestinationPath $ReleaseZip -Force

if ($KeepStaging) {
    Write-Host "  [KEEP] Staging dir: $StagingDir" -ForegroundColor Yellow
} else {
    Remove-Item $StagingDir -Recurse -Force
}

$SizeMB = [math]::Round((Get-Item $ReleaseZip).Length / 1MB, 1)
Write-Host "`n[OK] $ReleaseZip  (${SizeMB}MB)" -ForegroundColor Green
