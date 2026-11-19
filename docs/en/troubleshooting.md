[简体中文](../zh/troubleshooting.md) | English

# Troubleshooting

Each entry follows "exact symptom → root cause → fix → verification". Start with the quick map.

## Quick Map

| Symptom | Most likely cause | Entry |
|---|---|---|
| `uv trampoline failed to canonicalize script path` | The folder moved; the launcher still holds the old absolute path | [1](#1-uv-trampoline-failed-to-canonicalize-script-path) |
| `error: The interpreter ... is externally managed` | PEP 668 marker still present, or `python -m pip` used directly | [2](#2-pep-668-externally-managed) |
| `TclError: Can't find a usable init.tcl` | Embeddable engine has no Tcl/Tk, or `TCL_LIBRARY` unset | [3](#3-tclerror-cant-find-a-usable-inittcl) |
| `[WARN] No entry point for xxx.exe` during packaging | The tool has no `entry_points.txt` and is not a trampoline | [4](#4-tool-has-no-entry_pointstxt) |
| `python -c` works after a move but tools still fail | Launchers not repaired, or `python -S` used | [5](#5-no-auto-repair-under-python--s) |
| Jupyter cannot start a kernel / kernel path errors | `kernel.json` holds old absolute paths | [6](#6-jupyter-kernels-and-editable-installs) |
| Double-clicking `App.exe` is blocked by SmartScreen | Unsigned binary from the internet | [7](#7-smartscreen-and-antivirus) |
| `uv pip install` says `No virtual environment found` or installs into the host | Not activated; uv has no pinned interpreter | [10](#10-uv-pip-install-targets-the-wrong-interpreter-or-errors) |
| A tool cannot find `pip.exe` | Launcher deleted, or PBS never shipped it | [11](#11-a-tool-cannot-find-pipexe) |
| pip's cache or packages land in the user profile | `PIP_CACHE_DIR` unset, or `--user` was used | [12](#12-pip-installs-into-the-user-directory) |
| Bootstrap reports `SHA256 mismatch` | Download does not match `checksums.psd1`, or the mirror/version is wrong | [13](#13-download-verification-failed-sha256-mismatch) |
| An offline machine cannot install a package | The release has no `wheels/` | [14](#14-offline-installs-and-lock-files) |

## 1. `uv trampoline failed to canonicalize script path`

**Symptom**

```text
error: uv trampoline failed to canonicalize script path
```

**Root cause:** pip/uv generated `python/Scripts/<tool>.exe` files bake the installing interpreter's absolute path into the file tail. After a move or rename that path no longer exists, and the launcher fails while canonicalizing it — before any of your Python code runs.

**Fix** (any of these rebuilds the shim):

```powershell
# Repair immediately
python .\scripts\repair.py .

# Or activate (checks the marker automatically)
. .\scripts\activate.ps1

# Or reinstall the tool
.\scripts\pip.ps1 install <package>
```

**Verify**

```powershell
python .\python\Scripts\<tool>.exe --help   # should work
Get-ChildItem .\python\Scripts\<tool>.exe   # ~7 KB, not 47/108 KB
```

To avoid it entirely: activate once after moving, or call `python -m <tool>`.

## 2. PEP 668: externally managed

**Symptom**

```text
error: The interpreter at ... is externally managed, and indicates the following:
This Python installation is managed by uv and should not be modified.
```

**Root cause:** the PBS engine ships an `EXTERNALLY-MANAGED` marker. `bootstrap.ps1` removes it; calling `python -m pip` directly, or reusing an unprocessed engine copy, can bring it back.

**Fix**

```powershell
# Preferred: the wrapper adds --break-system-packages when needed
.\scripts\pip.ps1 install <package>

# Or remove the marker (this repository owns the interpreter)
Remove-Item .\python\Lib\site-packages\EXTERNALLY-MANAGED -ErrorAction SilentlyContinue
```

**Verify:** `.\scripts\pip.ps1 install <package>` completes without the error.

## 3. `TclError: Can't find a usable init.tcl`

**Symptom:** `import tkinter` or a GUI app fails with `TclError` listing several `tcl8.x` paths.

**Root cause:** the official embeddable engine has no Tcl/Tk, and `TCL_LIBRARY` / `TK_LIBRARY` are only set by an activated shell or by `App.exe` — not when an IDE invokes the interpreter directly.

**Fix**

```powershell
# Embeddable engine: add Tcl/Tk
.\scripts\add_tkinter.ps1

# Or switch to PBS, which bundles it
.\scripts\bootstrap.ps1 -Engine pbs
```

**Verify**

```powershell
. .\scripts\activate.ps1
python -m tkinter
```

If it only fails inside the IDE, add `TCL_LIBRARY` / `TK_LIBRARY` to the run configuration, or activate before launching.

## 4. Tool has no `entry_points.txt`

**Symptom:** `build_release.ps1` prints `[WARN] No entry point for xxx.exe`, and the tool breaks after a move.

**Root cause:** some packages expose commands without `console_scripts` (legacy `scripts=`, or a binary shipped directly in the wheel). Without metadata the entry point cannot be determined.

**Fix**

- If the file is a pip/uv launcher, `repair.py` recovers `module:func` from the `__main__.py` payload and repairs it automatically.
- If it is a real binary (`ruff`, `uv`), it contains no Python path and needs no repair; packaging copies it untouched.
- Otherwise `build_release.ps1` keeps the original file and warns instead of silently dropping it.

**Verify**

```powershell
Get-ChildItem .\python\Scripts\*.entry   # does the problematic tool have one?
```

Day to day, prefer `python -m <tool>` to bypass this layer.

## 5. No auto-repair under `python -S`

**Symptom:** after a move, `python -c "..."` works but launchers stay broken; or behavior changes with `-S`.

**Root cause:** `sitecustomize.py` runs through `import site`; `-S` skips it, so no hook under `site-packages` executes.

**Fix:** start with `site` enabled, or repair explicitly:

```powershell
python .\scripts\repair.py .
. .\scripts\activate.ps1
```

**Verify:** `Get-Content .\python\.portable_root` equals the current package root.

## 6. Jupyter Kernels and Editable Installs

**Symptom:** after moving, the Jupyter kernel fails to start, or your own package raises `ModuleNotFoundError`.

**Root cause**

- `kernel.json` stores the interpreter's absolute path in `argv`. `activate.ps1` points `JUPYTER_DATA_DIR` inside the package, but the content is still stale.
- `pip install -e` writes `__editable__*.pth` files containing absolute paths.

**Fix**

```powershell
. .\scripts\activate.ps1
python -m ipykernel install --prefix .\python --name portable --display-name "Portable Python"

# Editable installs: reinstall to rewrite the .pth
.\scripts\pip.ps1 install -e .\my_pkg
```

**Verify**

```powershell
python -m jupyter kernelspec list
Get-Content .\python\share\jupyter\kernels\*\kernel.json
```

## 7. SmartScreen and Antivirus

**Symptom:** "Windows protected your PC" when double-clicking `App.exe`, or the file gets quarantined.

**Root cause:** `App.exe` is unsigned, and browser downloads carry Mark-of-the-Web.

**Fix:** distribute inside a ZIP (extraction usually clears the prompt), sign the binary for direct distribution, or unblock it locally:

```powershell
Unblock-File .\App.exe
```

**Verify:** double-clicking starts the app without a prompt.

## 8. Non-ASCII and Long Paths

**Symptom:** path-too-long or file-not-found during install/extract; occasional `UnicodeDecodeError`.

**Root cause:** the 260-character default limit on Windows, plus inconsistent non-ASCII handling in some tools.

**Fix:** place the package at a short ASCII path (e.g. `D:\py`) and enable long paths:

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled 1
```

## 9. Seeing `[repair] N launcher(s) rebuilt`

This is **expected output**, not an error. It appears when:

- an interpreter starts for the first time after the folder was moved or copied (including the first run of an extracted release), or
- a package was just installed or uninstalled.

If it appears on every start, `.portable_root` is not being written (read-only directory, or blocked by security software). Check that the file exists and holds the current package root.

## 10. `uv pip install` targets the wrong interpreter or errors

**Symptom**

```text
error: No virtual environment found; run `uv venv` to create an environment,
       or pass `--system` to install into a non-virtual environment
```

Or, more subtly: the command succeeds, but `uv pip list` shows packages from a host interpreter such as `C:\Users\...\AppData\Roaming\uv\python\cpython-3.12...`.

**Root cause:** uv is a standalone binary and does not inherit this project's interpreter choice. Without activation it discovers its own Python, or refuses when no virtual environment exists.

**Fix**

```powershell
# Option 1: activate, then the UV_* variables pin uv for this shell
. .\scripts\activate.ps1
uv pip install <package>

# Option 2: always go through the wrapper
.\scripts\pip.ps1 install <package>
```

**Verify**

```powershell
uv pip list | Select-Object -First 3   # header should show Using Python ...\python
```

Note: `uv.toml` cannot solve this — its `python` key resolves relative paths against the working directory, and an absolute path breaks after a move.

## 11. A tool cannot find `pip.exe`

**Symptom:** a tool raises `FileNotFoundError: ...\python\Scripts\pip.exe`, or reports that `pip` is not recognized.

**Root cause:** the PBS engine does not ship `pip.exe`; it only appears through `get-pip` or a pip self-upgrade, and it may also have been deleted.

**Fix**

```powershell
python .\scripts\repair.py .
```

`repair` reads `entry_points.txt` and recreates missing commands as `shim.exe` copies plus `.entry` sidecars.

**Verify**

```powershell
Get-ChildItem .\python\Scripts\pip*.exe | Select-Object Name, Length   # about 7 KB
.\python\Scripts\pip.exe --version
```

## 12. pip installs into the user directory

**Symptom:** freshly installed packages are missing from the package environment; they appear under `%APPDATA%\Python\Python3xx\site-packages`; or `%LOCALAPPDATA%\pip\Cache` keeps growing.

**Root cause:** `pip install --user` was used, or the environment did not inherit `PYTHONNOUSERSITE` / `PIP_CACHE_DIR`.

**Fix**

```powershell
. .\scripts\activate.ps1        # sets PYTHONNOUSERSITE, PIP_USER, PIP_CACHE_DIR
.\scripts\pip.ps1 install <package>
```

`sitecustomize.py` also fills these defaults for the current process and its children, so tools spawned from the in-package interpreter are protected too.

**Verify**

```powershell
python -m pip config list
python -c "import site; print(site.ENABLE_USER_SITE)"
Test-Path .\python\.pip_cache
```

## 13. Download verification failed (SHA256 mismatch)

**Symptom:** bootstrap or `add_tkinter.ps1` prints `SHA256 mismatch ...` and exits.

**Cause:** the downloaded file does not match `scripts/checksums.psd1`, usually because a mirror is stale, the version/arch is wrong, or upstream `get-pip.py` changed.

**Fix**

```powershell
# Retry with the official source or a trusted mirror
.\scripts\bootstrap.ps1

# Override the hash after verifying the mirror content yourself
.\scripts\bootstrap.ps1 -PythonSha256 <hex>
.\scripts\bootstrap.ps1 -GetPipSha256 <hex>
.\scripts\add_tkinter.ps1 -Sha256 <hex>

# Trusted offline artifact only
.\scripts\bootstrap.ps1 -SkipChecksum

# New patch / new architecture: refresh the hash table
.\scripts\update_checksums.ps1 -Version 3.14.10 -Arch amd64,arm64,win32
```

Bootstrap verifies before swapping, so a failure leaves the old `python/` untouched; the leftover `python.new` can be deleted.

**Verify:** `python -V` still reports the old environment; rerun bootstrap once the source is fixed.

## 14. Offline installs and lock files

**Symptom:** the target machine is offline and needs another package; or two bootstrap runs resolve different versions.

**Fix**

```powershell
# Hash-pinned lock file; bootstrap prefers it when restoring
.\scripts\pip.ps1 lock

# Build a release with an offline wheelhouse
.\scripts\build_release.ps1 -Wheelhouse
```

Inside the extracted package, `sitecustomize.py` sets `PIP_FIND_LINKS` and `UV_FIND_LINKS`, so this works without a network:

```powershell
python -m pip install --no-index <package>
```

**Verify**

```powershell
python -c "import os; print(os.environ.get('PIP_FIND_LINKS'))"   # points at the in-package wheels
Test-Path .\requirements.lock
Test-Path .\wheels
```

## 15. Consumer Mode and Scaffolding

**Symptom A**: the generated `build-<app>.ps1` fails with `Submodule missing at ...`.

```powershell
git submodule update --init --recursive
```

For projects generated with `-SkipSubmodule`, add the submodule manually, or use a junction to this checkout for local testing.

**Symptom B**: a `-Profile multi` build never finishes, the `.portable` folder grows without bound, and nested `.portable/app/.portable/...` directories appear.

The old template copied the whole app directory into `<app>/.portable/app`, but in the multi layout `.portable` lives inside the app directory, so the copy fed on itself. Regenerate with the updated scaffold:

```powershell
.\scripts\new-portable-project.ps1 -Profile multi -ProjectRoot <project> -AppDirs apps/one,apps/two -Force
```

**Symptom C**: a `-Profile scripts` project needs a runtime upgrade.

`scripts/` is a checked-in copy, not a submodule. Re-run the scaffold with `-Force` to replace it, then run `.\scripts\build.ps1` again. Your code and `requirements.txt` are untouched.

**Verify**

```powershell
Test-Path .\scripts\build-portable.ps1          # app
Test-Path .\scripts\build.ps1                  # scripts
Test-Path .\scripts\build-all.ps1              # multi
Test-Path .\apps\one\.portable\dist            # multi: one output per app
```

## Collecting Diagnostics

```powershell
python -V
python -c "import sys; print(sys.prefix); print(sys.executable)"
Get-Content .\python\.portable_root
Get-ChildItem .\python\Scripts\*.entry | Select-Object Name, Length
Get-ChildItem .\python\Lib\site-packages\*.dist-info -Directory | Measure-Object
Test-Path .\scripts\bin\shim.exe
```

Attaching this output to a bug report is enough to diagnose most relocation failures.
