# scripts/build_release.ps1
# Streams the workspace directly into a distributable ZIP: .exe launchers are
# replaced by relative-path .bat wrappers and extensionless-script shebangs are
# rewritten on the fly — no staging copy, nothing lands on disk twice.

param(
    [Parameter(Mandatory=$false)]
    [string]$ReleaseName = "Portable_Python",
    [Parameter(Mandatory=$false)]
    [switch]$AppendDateTime
)

$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$DistDir      = Join-Path $WorkspaceDir "dist"

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Force $DistDir | Out-Null }

if ($AppendDateTime) {
    $TimeStamp  = Get-Date -Format "yyyyMMdd_HHmm"
    $ReleaseZip = Join-Path $DistDir "$ReleaseName`_$TimeStamp.zip"
} else {
    $ReleaseZip = Join-Path $DistDir "$ReleaseName.zip"
}

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }

# ---------- cleanup previous ----------

if (Test-Path $ReleaseZip) { Remove-Item $ReleaseZip -Force }
if (Test-Path (Join-Path $WorkspaceDir "_release_staging")) {
    Remove-Item (Join-Path $WorkspaceDir "_release_staging") -Recurse -Force
    Write-Host "  [DEL] leftover _release_staging/ from previous runs"
}

# ---------- stream workspace into ZIP ----------

Write-Step "[1/2] Streaming runtime files into archive..."

$LocalPythonExe = Join-Path $WorkspaceDir "python\python.exe"

$PyZipScript = @'
import configparser, re, sys, zipfile
from pathlib import Path

workspace    = Path(sys.argv[1]).resolve()
zip_path     = Path(sys.argv[2])
scripts_root = workspace / "python" / "Scripts"
site_pkgs    = workspace / "python" / "Lib" / "site-packages"

JUNK_DIRS = {"__pycache__", ".pip_cache"}
JUNK_EXTS = {".pyc", ".pyo"}
counts = {"files": 0, "wrapped": 0, "patched": 0}

# ---- entry-point map (name -> (module, func)) for .bat generation ----
ep_map = {}
for dist_info in sorted(site_pkgs.glob("*.dist-info")):
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
            ep_map[name.strip().lower()] = (module, attrs if attrs else "main")

def bat_for(stem):
    key = stem.lower()
    if key not in ep_map:
        base = re.sub(r"[\d.]+$", "", key)
        if base in ep_map:
            key = base
    if key in ep_map:
        module, func = ep_map[key]
        return (f'@echo off\r\n'
                f'set "PYTHONNOUSERSITE=1"\r\n'
                f'"%~dp0..\\python.exe" -c "import sys; from {module} import {func}; sys.exit({func}())" %*\r\n')
    print(f"  [WARN] No entry_point for {stem}.exe, using -m {stem.lower()}")
    return (f'@echo off\r\n'
            f'set "PYTHONNOUSERSITE=1"\r\n'
            f'"%~dp0..\\python.exe" -m {stem.lower()} %*\r\n')

def add_tree(base, arc_prefix, strip_pdf=False):
    for entry in sorted(base.iterdir(), key=lambda p: p.name):
        if entry.is_dir():
            if entry.name in JUNK_DIRS:
                continue
            add_tree(entry, f"{arc_prefix}{entry.name}/", strip_pdf)
        else:
            if entry.suffix in JUNK_EXTS:
                continue
            if strip_pdf and entry.suffix == ".pdf":
                continue
            zf.write(entry, f"{arc_prefix}{entry.name}")
            counts["files"] += 1

def add_scripts():
    if not scripts_root.exists():
        return
    for entry in sorted(scripts_root.iterdir(), key=lambda p: p.name):
        if entry.is_dir():
            add_tree(entry, f"python/Scripts/{entry.name}/")
        elif entry.suffix == ".exe":
            zf.writestr(f"python/Scripts/{entry.stem}.bat", bat_for(entry.stem))
            counts["wrapped"] += 1
        elif not entry.suffix:
            # extensionless script: rewrite the absolute python shebang in-flight
            data = entry.read_bytes()
            first, sep, rest = data.partition(b"\n")
            if first.startswith(b"#!") and b"python.exe" in first.lower():
                data = b"#!..\\python.exe\n" + rest
                counts["patched"] += 1
            zf.writestr(f"python/Scripts/{entry.name}", data)
            counts["files"] += 1
        else:
            zf.write(entry, f"python/Scripts/{entry.name}")
            counts["files"] += 1

def add_python():
    for entry in sorted((workspace / "python").iterdir(), key=lambda p: p.name):
        if entry.name == "Scripts" and entry.is_dir():
            add_scripts()
        elif entry.is_dir():
            if entry.name in JUNK_DIRS:
                continue
            add_tree(entry, f"python/{entry.name}/")
        else:
            if entry.suffix in JUNK_EXTS:
                continue
            zf.write(entry, f"python/{entry.name}")
            counts["files"] += 1

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    # app dirs (top-level, not dot-prefixed) + top-level .bat launchers
    exclude_top = {"python", "scripts", "dist", "_release_staging", "__pycache__"}
    for entry in sorted(workspace.iterdir(), key=lambda p: p.name):
        if entry.name in {"python", "scripts"}:
            continue
        if entry.is_dir():
            if entry.name.startswith(".") or entry.name in exclude_top:
                continue
            add_tree(entry, f"{entry.name}/", strip_pdf=(entry.name == "pdf"))
            print(f"  [ADD] {entry.name}/")
        elif entry.is_file() and entry.suffix == ".bat":
            zf.write(entry, entry.name)
            counts["files"] += 1
            print(f"  [ADD] {entry.name}")

    # PowerShell tooling
    add_tree(workspace / "scripts", "scripts/")

    # Python engine (Scripts handled specially)
    add_python()

print(f"\n  {counts['files']} files, {counts['wrapped']} .bat wrappers generated, "
      f"{counts['patched']} shebangs patched")
'@

& $LocalPythonExe -c $PyZipScript $WorkspaceDir $ReleaseZip
if ($LASTEXITCODE -ne 0) { throw "ZIP streaming failed (exit $LASTEXITCODE)" }

# ---------- done ----------

$SizeMB = [math]::Round((Get-Item $ReleaseZip).Length / 1MB, 1)
Write-Host "`n[2/2] $ReleaseZip  (${SizeMB}MB)" -ForegroundColor Green
