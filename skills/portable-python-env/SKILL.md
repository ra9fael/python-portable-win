---
name: portable-python-env
description: Use when working inside a portable Python workspace produced by this repository — installing packages, running scripts or CLI tools, copying/moving the folder, or building a release. Covers bootstrap, activation, the shim/repair mechanism, and the failures that appear after relocation. Do not use for unrelated Python projects that are not rooted at a package directory containing python/python.exe.
---

# Portable Python Environment

A self-contained Windows Python workspace: one directory holds the interpreter, a flat `site-packages`, and tooling. The folder can be copied to any path and keeps working.

## When to use

- The project root contains `python/python.exe`, `scripts/bootstrap.ps1`, `scripts/pip.ps1`, `app.ini`.
- The user asks to install dependencies, run scripts/tests/tools, move the folder, upgrade Python, or package a release.
- A tool fails with `uv trampoline failed to canonicalize script path` or similar after a move.

## When not to use

- The project uses a normal venv/conda/Poetry/uv project environment and has no `python/python.exe` under its root.
- The task is unrelated Python editing with no environment operations.

## 60-second start

```powershell
.\scripts\bootstrap.ps1            # only if python\ is missing
. .\scripts\activate.ps1           # dot-source; required for PATH and Tcl/Tk
python -V
```

Bootstrap installs python-build-standalone via `uv` when available (bundled Tcl/Tk), otherwise the official embeddable engine, then installs the startup hook and `scripts/bin/shim.exe`.

## Invariants — do not break these

1. `python/` is generated and git-ignored. Rebuild it with `bootstrap.ps1`; never hand-edit files inside it.
2. Install and remove packages only through `scripts/pip.ps1`. It isolates caches, handles PEP 668, and rewrites launchers afterwards.
3. Never edit `.exe` files in `python/Scripts/`. They are regenerated: `shim.exe` copies plus a `<name>.entry` sidecar.
4. Prefer `python -m <tool>` over calling `python/Scripts/<tool>.exe`. It bypasses the launcher layer entirely.
5. Do not use `pip install -e`. Editable installs leave absolute paths in `__editable__*.pth` that break on relocation.
6. Never modify the host `PATH`, registry, or `%APPDATA%` state. Activation is session-scoped; `deactivate` restores it.
7. Do not pass `--user` to pip. Use `scripts/pip.ps1` or an activated shell so `PIP_USER=0` and the in-package cache apply.
8. If you use uv directly, activate first (`UV_SYSTEM_PYTHON=1`, `UV_PYTHON`, `UV_CACHE_DIR` are set for you).
9. Compiled artifacts (Cython `.pyd`, Nuitka output) are an application-layer concern. Stage them into `<workspace>/app`; they must be built for the same minor version and architecture as the bundled engine, and the matching `.py` must be removed from the release.

## Task recipes

| Task | Command | Verify |
|---|---|---|
| Activate | `. .\scripts\activate.ps1` | `python -V` shows the package interpreter |
| Install packages | `.\scripts\pip.ps1 install <pkg>` | `python -c "import <pkg>"` |
| Install with uv | `. .\scripts\activate.ps1` then `uv pip install <pkg>` | `uv pip list` header shows `...\python` |
| Install from file | `.\scripts\pip.ps1 install -r requirements.txt` | same |
| Generate a lock | `.\scripts\pip.ps1 lock` | `requirements.lock` has hashes |
| Uninstall | `.\scripts\pip.ps1 uninstall <pkg>` | package gone, no stale `.entry` |
| Run a script | `python path\to\script.py` | exit code 0 |
| Run a tool | `python -m pytest` / `python -m jupyter lab` | tool starts |
| Rebuild shims | `.\scripts\build_launcher.ps1 -ShimOnly` | `scripts/bin/shim.exe` exists |
| Build optional launcher | `.\scripts\build_launcher.ps1` | `App.exe` exists |
| Package release | `.\scripts\build_release.ps1` | ZIP in `dist/` |
| Build a consumer workspace | `.\scripts\new-portable-project.ps1 -ProjectRoot <app> -AppDir app -Requirements requirements.txt` then run `<app>\scripts\build-portable.ps1` | `<app>\.portable\dist\*.zip`; upstream checkout unchanged |
| Scaffold a personal script workspace | `.\scripts\new-portable-project.ps1 -Profile scripts -ProjectRoot <dir> -AppDir my_tools` then run `<dir>\scripts\build.ps1` | ZIP in `<dir>\dist\`; no submodule |
| Scaffold a multi-app repo | `.\scripts\new-portable-project.ps1 -Profile multi -ProjectRoot <dir> -AppDirs apps/one,apps/two` then run `<dir>\scripts\build-all.ps1` | one `<app>\.portable\dist\*.zip` per app |
| Offline release | `.\scripts\build_release.ps1 -Wheelhouse` | `wheels/` inside the ZIP |
| Refresh download hashes | `.\scripts\update_checksums.ps1 -Version 3.14.10 -Arch amd64,arm64,win32` | `checksums.psd1` has the new entries |
| Upgrade Python | edit `$Version`, rerun `bootstrap.ps1` | `python -V` matches |

Force an engine or version:

```powershell
.\scripts\bootstrap.ps1 -Engine pbs -Version 3.13.7
.\scripts\bootstrap.ps1 -Engine embeddable
```

Restricted network and unattended runs:

```powershell
.\scripts\bootstrap.ps1 -Mirror https://mirror.example.com/python -PipIndexUrl https://mirror.example.com/pypi/simple
.\scripts\bootstrap.ps1 -NonInteractive
```

Downloads are checked against `scripts/checksums.psd1`; a mismatch aborts before the staged engine replaces `python/`. Override with `-PythonSha256` / `-GetPipSha256`, or use `-SkipChecksum` only for a trusted artifact. The exact installed patch version is recorded in `python/.portable_version` and reused when `-Version` is omitted.

## After moving or copying the folder

1. Re-open the shell at the new path and dot-source `activate.ps1`. It compares `python/.portable_root` and repairs stale launchers.
2. Expect one line such as `[repair] N launcher(s) rebuilt` — this is normal, not an error.
3. Run `python -V` to trigger the `sitecustomize` check if activation was skipped.
4. Jupyter kernels keep absolute paths in `kernel.json`; recreate them:

```powershell
. .\scripts\activate.ps1
python -m ipykernel install --prefix .\python --name portable --display-name "Portable Python"
```

## When something fails

| Symptom | Action |
|---|---|
| `uv trampoline failed to canonicalize script path` | `python .\scripts\repair.py .` then retry |
| `is externally managed` | Use `.\scripts\pip.ps1`; if it persists, delete `python\Lib\site-packages\EXTERNALLY-MANAGED` |
| `TclError: Can't find a usable init.tcl` | `.\scripts\add_tkinter.ps1` (embeddable), or use `-Engine pbs` |
| uv reports `No virtual environment found` or installs into the host | Activate first, or use `.\scripts\pip.ps1` |
| A tool cannot find `pip.exe` | `python .\scripts\repair.py .` recreates it from metadata |
| `[repair]` on every start | `.portable_root` cannot be written — check permissions/antivirus |
| Repair seems skipped | `python -S` bypasses `sitecustomize`; repair explicitly |

Detailed diagnosis: `docs/en/troubleshooting.md` (Chinese: `docs/zh/troubleshooting.md`).

## Verify environment health

```powershell
python -V
python -c "import sys; print(sys.prefix); print(sys.executable)"
Get-Content .\python\.portable_root
Get-ChildItem .\python\Scripts\*.entry | Measure-Object
Test-Path .\scripts\bin\shim.exe
```

`sys.prefix` must be the `python/` directory of the current workspace, and `.portable_root` must equal the package root.

## References

- `reference.md` — script CLI options, repair internals, release manifest, measured facts.
- `docs/en/architecture.md` — why relocation works; launcher comparison.
- `AGENTS.md` — repository conventions when modifying this project itself.
