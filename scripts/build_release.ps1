# scripts/build_release.ps1
# Streams the workspace directly into a distributable ZIP: App.exe / shim.exe
# replace every .bat entry point, and console-script launchers are rewritten as
# path-relative shims — no staging copy, nothing lands on disk twice.

param(
    [Parameter(Mandatory=$false)]
    [string]$ReleaseName = "",
    [Parameter(Mandatory=$false)]
    [string]$Arch = "amd64",
    [Parameter(Mandatory=$false)]
    [switch]$AppendDateTime,
    # Collect every installed dependency (with dependencies) into wheels/ so the
    # package can install offline.
    [Parameter(Mandatory=$false)]
    [switch]$Wheelhouse,
    # Consumer mode: package this workspace (e.g. <app>\.portable) instead of scripts/..
    [Parameter(Mandatory=$false)]
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
$RuntimeScripts = Initialize-PortableRuntime -WorkspaceDir $WorkspaceDir -ScriptDir $ScriptDir
$DistDir      = Join-Path $WorkspaceDir "dist"
$LocalPythonExe = Join-Path $WorkspaceDir "python\python.exe"
$LauncherExe  = Join-Path $WorkspaceDir "App.exe"
$ShimExe      = Join-Path $RuntimeScripts "bin\shim.exe"

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Force $DistDir | Out-Null }

# shim.exe is required at runtime (repair payload); App.exe is an optional sample.
if (-not (Test-Path $ShimExe)) {
    Write-Host "  shim.exe missing, building repair payload..." -ForegroundColor Yellow
    & (Join-Path $ScriptDir "build_launcher.ps1") -ShimOnly -Workspace $WorkspaceDir
}

if (-not (Test-Path $ShimExe)) {
    throw "$ShimExe not found — run scripts\build_launcher.ps1 -ShimOnly -Workspace $WorkspaceDir first."
}

if (-not (Test-Path $LauncherExe)) {
    Write-Host "  App.exe not found — packaging without a launcher." -ForegroundColor Yellow
}

if (-not $ReleaseName) {
    if (-not (Test-Path $LocalPythonExe)) {
        throw "python\python.exe not found — run bootstrap.ps1 first or pass -ReleaseName explicitly."
    }
    $PyVersion = (& $LocalPythonExe -V).Trim() -replace '^Python\s+', ''
    $WorkspaceName = Split-Path $WorkspaceDir -Leaf
    if ($WorkspaceName.StartsWith(".")) {
        # .portable/ -> use the app folder name, not ".portable".
        $WorkspaceName = Split-Path (Split-Path $WorkspaceDir -Parent) -Leaf
    }
    $ReleaseName = "$WorkspaceName`_Python$PyVersion`_$Arch"
    Write-Host "  Using release name: $ReleaseName"
}

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

# ---------- optional offline wheelhouse ----------

$WheelDir = Join-Path $WorkspaceDir "wheels"
if ($Wheelhouse) {
    Write-Step "[1/3] Collecting offline wheelhouse..."
    if (Test-Path $WheelDir) { Remove-Item $WheelDir -Recurse -Force }
    New-Item -ItemType Directory -Force $WheelDir | Out-Null

    $WheelReq = Join-Path $WorkspaceDir "requirements.txt"
    $TempReq = $null
    if (-not (Test-Path $WheelReq)) {
        $TempReq = Join-Path $env:TEMP "portable-wheelhouse-$PID.txt"
        & $LocalPythonExe -m pip freeze |
            Where-Object { $_ -and $_ -notmatch '^pip @ ' } |
            Set-Content $TempReq -Encoding ASCII
        $WheelReq = $TempReq
    }

    & $LocalPythonExe -m pip download -r $WheelReq -d $WheelDir --prefer-binary
    if ($TempReq) { Remove-Item $TempReq -Force -ErrorAction SilentlyContinue }
    if ($LASTEXITCODE -ne 0) { throw "pip download failed (exit $LASTEXITCODE)" }

    $WheelCount = (Get-ChildItem $WheelDir -File | Measure-Object).Count
    Write-Host "  [OK] $WheelCount wheel(s)/sdist(s) collected in wheels/" -ForegroundColor Green
}

# ---------- stream workspace into ZIP ----------

Write-Step "[2/3] Streaming runtime files into archive..."

$PyZipScript = @'
import configparser, re, sys, zipfile
from pathlib import Path

workspace    = Path(sys.argv[1]).resolve()
zip_path     = Path(sys.argv[2])
include_wheels = len(sys.argv) > 3 and sys.argv[3] == "1"
scripts_root = workspace / "python" / "Scripts"
site_pkgs    = workspace / "python" / "Lib" / "site-packages"
shim_path    = workspace / "scripts" / "bin" / "shim.exe"

# Reuse the runtime repair helpers so packaging and self-healing cannot drift.
sys.path.insert(0, str(workspace / "scripts"))
import repair as repair_helpers

JUNK_DIRS = {"__pycache__", ".pip_cache", ".uv_cache"}
JUNK_FILES = {".portable_root"}
JUNK_EXTS = {".pyc", ".pyo"}
ROOT_FILES = {"App.exe", "app.ini", "README.md", "README.en.md"}
counts = {"files": 0, "wrapped": 0, "skipped": 0}
shim_bytes = shim_path.read_bytes() if shim_path.exists() else None

# ---- entry-point map (name -> module, func, gui) for shim generation ----
ep_map = {}
for dist_info in sorted(site_pkgs.glob("*.dist-info")):
    ep_file = dist_info / "entry_points.txt"
    if not ep_file.exists():
        continue
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ep_file, encoding="utf-8")
    for section in ("console_scripts", "gui_scripts"):
        if section not in cfg.sections():
            continue
        for name, value in cfg.items(section):
            raw = value.split("[")[0].strip()
            module, _, attrs = raw.partition(":")
            ep_map[name.strip().lower()] = (
                module, attrs.strip() or "main", section == "gui_scripts"
            )

def bat_for(stem):
    key = stem.lower()
    if key not in ep_map:
        base = re.sub(r"[\d.]+$", "", key)
        if base in ep_map:
            key = base
    if key in ep_map:
        module, func, gui = ep_map[key]
        python = "pythonw.exe" if gui else "python.exe"
        return (f'@echo off\r\n'
                f'set "PYTHONNOUSERSITE=1"\r\n'
                f'"%~dp0..\\{python}" -c "import sys; from {module} import {func}; sys.exit({func}())" %*\r\n')
    return None

def find_meta(stem):
    return repair_helpers.find_entry(ep_map, stem)

def sidecar_entry(exe):
    """Read <stem>.entry written by an earlier repair, if present."""
    sidecar = exe.with_suffix(".entry")
    if not sidecar.exists():
        return None
    values = {}
    try:
        for line in sidecar.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            values[key.strip().lower()] = value.strip()
    except OSError:
        return None
    if not values.get("module"):
        return None
    return values["module"], values.get("func") or "main", values.get("gui") == "true"

def wrap_for(exe):
    """Replace one launcher with shim + .entry, falling back to a .bat wrapper."""
    stem = exe.stem
    meta = sidecar_entry(exe) or find_meta(stem) or repair_helpers.entry_from_exe(exe)
    if meta and shim_bytes:
        module, func, gui = meta
        zf.writestr(f"python/Scripts/{stem}.exe", shim_bytes)
        zf.writestr(
            f"python/Scripts/{stem}.entry",
            f"module={module}\nfunc={func}\ngui={'true' if gui else 'false'}\n",
        )
        counts["wrapped"] += 1
        return True
    bat = bat_for(stem)
    if bat:
        zf.writestr(f"python/Scripts/{stem}.bat", bat)
        counts["wrapped"] += 1
        return True
    print(f"  [WARN] No entry point for {exe.name}")
    return False

def add_tree(base, arc_prefix, strip_pdf=False):
    for entry in sorted(base.iterdir(), key=lambda p: p.name):
        if entry.is_dir():
            if entry.name in JUNK_DIRS:
                continue
            add_tree(entry, f"{arc_prefix}{entry.name}/", strip_pdf)
        else:
            if entry.suffix in JUNK_EXTS:
                continue
            if entry.name in JUNK_FILES:
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
            is_shim = shim_bytes is not None and entry.stat().st_size == len(shim_bytes)
            if is_shim or repair_helpers.is_trampoline(entry):
                if not wrap_for(entry):
                    # Never drop a tool silently: keep the original launcher.
                    zf.write(entry, f"python/Scripts/{entry.name}")
                    counts["skipped"] += 1
            else:
                # Real compiled binary (e.g. ruff); it does not embed a Python path.
                zf.write(entry, f"python/Scripts/{entry.name}")
                counts["files"] += 1
        elif entry.suffix == ".entry":
            # regenerated next to each shim
            continue
        elif not entry.suffix:
            if entry.name in JUNK_FILES:
                continue
            # extensionless script: rewrite the absolute python shebang in-flight
            data = entry.read_bytes()
            first, sep, rest = data.partition(b"\n")
            if first.startswith(b"#!") and b"python.exe" in first.lower():
                data = b"#!..\\python.exe\n" + rest
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
            if entry.suffix in JUNK_EXTS or entry.name in JUNK_FILES:
                continue
            zf.write(entry, f"python/{entry.name}")
            counts["files"] += 1

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    # app dirs (top-level, not dot-prefixed), launcher, config and docs
    exclude_top = {"python", "scripts", "dist", "_release_staging", "python_pbs_tmp", "__pycache__"}
    if not include_wheels:
        exclude_top.add("wheels")
    for entry in sorted(workspace.iterdir(), key=lambda p: p.name):
        if entry.name in {"python", "scripts"}:
            continue
        if entry.is_dir():
            if entry.name.startswith(".") or entry.name == ".vscode":
                continue
            if entry.name in exclude_top:
                continue
            add_tree(entry, f"{entry.name}/", strip_pdf=(entry.name == "pdf"))
            print(f"  [ADD] {entry.name}/")
        elif entry.is_file():
            if entry.name in ROOT_FILES or entry.name.startswith("requirements") or entry.suffix.lower() in {".bat", ".cmd", ".ini"}:
                zf.write(entry, entry.name)
                counts["files"] += 1
                print(f"  [ADD] {entry.name}")

    # dev configuration is part of the portable package
    vscode = workspace / ".vscode"
    if vscode.exists():
        add_tree(vscode, ".vscode/")
        print("  [ADD] .vscode/")

    # PowerShell tooling (includes repair.py and bin/shim.exe)
    add_tree(workspace / "scripts", "scripts/")

    # Python engine (Scripts handled specially)
    add_python()

print(f"\n  {counts['files']} files, {counts['wrapped']} launchers generated, "
      f"{counts['skipped']} binaries left as-is")
'@

& $LocalPythonExe -c $PyZipScript $WorkspaceDir $ReleaseZip $(if ($Wheelhouse) { "1" } else { "0" })
if ($LASTEXITCODE -ne 0) { throw "ZIP streaming failed (exit $LASTEXITCODE)" }

# ---------- done ----------

$SizeMB = [math]::Round((Get-Item $ReleaseZip).Length / 1MB, 1)
Write-Host "`n[3/3] $ReleaseZip  (${SizeMB}MB)" -ForegroundColor Green
