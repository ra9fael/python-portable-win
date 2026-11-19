# Reference — portable-python-env

Technical detail behind `SKILL.md`. Safe to read on demand; nothing here changes the invariants.

## Layout

| Path | Role |
|---|---|
| `python/` | Generated interpreter + `Lib/site-packages`. Git-ignored. |
| `python/Scripts/` | Tool launchers: `shim.exe` copies + `<name>.entry` sidecars. |
| `python/.portable_root` | Text file holding the package root that last repaired the tree. |
| `scripts/bootstrap.ps1` | Installs engine, prepares pip, installs the hook, builds the shim. |
| `scripts/activate.ps1` | Dot-sourced env setup + repair check. |
| `scripts/pip.ps1` | Isolated installer; repairs launchers on success. |
| `scripts/repair.py` | Importable `repair(root)`; also a CLI. |
| `scripts/sitecustomize.py` | Copied into `site-packages`; runs the check on every start. |
| `scripts/build_launcher.ps1` | Compiles `launcher/Shim.cs`, and `launcher/Launcher.cs` unless `-ShimOnly`. |
| `scripts/bin/shim.exe` | Build artifact, git-ignored. Required by `repair.py`. |
| `scripts/build_release.ps1` | Streams the workspace into a distributable ZIP. |
| `scripts/workspace.ps1` | Resolves `-Workspace` and stages runtime scripts for consumer builds. |
| `scripts/selftest.ps1` | Copies `python/` to a temp tree and checks repair, launcher recreation, trampoline conversion and a real move. |
| `docs/{zh,en}/` | Architecture and troubleshooting. |

Consumer-mode convention: an app keeps generated files in `<app>/.portable/` and passes `-Workspace <app>/.portable`; the upstream checkout is never written to.

Compiled artifacts (Cython `.pyd`, Nuitka output) are not produced here. Stage them into `<workspace>/app`, build them for the engine's exact minor version and architecture, and drop the corresponding `.py` from the staged tree before `build_release.ps1`. The embeddable engine has no headers; PBS does.

## Script options

### `new-portable-project.ps1`

| Option | Meaning |
|---|---|
| `-ProjectRoot` | Target project directory (created if missing) |
| `-Profile` | `app` (default), `scripts`, or `multi` |
| `-AppDir` | `app`/`scripts`: app source directory relative to the project root |
| `-AppDirs` | `multi`: comma or array of app directories (e.g. `apps/one,apps/two`) |
| `-Requirements` | Requirements file relative to the project root; `multi` defaults to `<app>/requirements.txt` |
| `-PythonVersion` | Version baked into the generated script |
| `-Workspace` | Workspace directory, default `.portable`; `multi` is relative to each app |
| `-SubmodulePath` | Submodule path, default `vendor/python-portable-win` |
| `-UpstreamUrl` | Submodule URL |
| `-Ref` | Tag/SHA to pin; defaults to this checkout's tag or SHA |
| `-SkipSubmodule` | Generate without touching git |
| `-Force` | Overwrite existing generated files (and replace a copied `scripts/`) |

Profiles:

- `app` — `scripts/build-portable.ps1` from `templates/consumer/build-portable.ps1`, submodule pinned, `.portable/` ignored.
- `scripts` — copies this repository's `scripts/` into the project (no submodule), writes `scripts/build.ps1`, `start.bat`, `<AppDir>/main.py`; ignores `python/`, `dist/`, `scripts/bin/`.
- `multi` — one `scripts/build-<app>.ps1` per app plus `build-all.ps1`; each app builds into `<app>/.portable`. Staging skips the workspace so it is never copied into itself.

`multi` and `app` stage the app with `templates/consumer/build-portable.ps1`; `scripts` uses `templates/scripts/*`.

### `bootstrap.ps1`

| Option | Values | Meaning |
|---|---|---|
| `-Version` | e.g. `3.14.7` | Python version to install; defaults to `python/.portable_version` when present |
| `-Arch` | `amd64` | Architecture for the embeddable download |
| `-Engine` | `auto` \| `pbs` \| `embeddable` | Engine selection; `auto` prefers PBS when `uv` exists |
| `-WithLauncher` | switch | Also compile `App.exe` |
| `-Mirror` | URL prefix | PBS: `uv python install --mirror`; embeddable: replaces the `python.org/ftp/python` prefix |
| `-PipIndexUrl` | URL | Sets `PIP_INDEX_URL` and `UV_INDEX_URL` for package installs |
| `-PythonSha256` | hex | Override the pinned embeddable ZIP hash |
| `-GetPipSha256` | hex | Override the pinned `get-pip.py` hash |
| `-SkipChecksum` | switch | Skip download verification (trusted offline artifact only) |
| `-NonInteractive` | switch | Never prompt; skip export/restore and the final pause |
| `-Workspace` | path | Consumer mode: build `python/` inside this directory (e.g. `.portable`) |
| `-ChecksumFile` | path | Alternative checksum table; defaults to `scripts/checksums.psd1` |

Behaviour: detects an existing `python/`, offers to export `requirements.txt`, stages the new engine under `python.new`, verifies downloads against `scripts/checksums.psd1`, swaps only after success, writes `python/.portable_version`, offers to restore `requirements.lock` (preferred) or `requirements.txt`, writes `python/pip.ini`, installs `sitecustomize.py`, builds the shim. PBS mode removes `EXTERNALLY-MANAGED`.

### `update_checksums.ps1`

| Option | Meaning |
|---|---|
| `-Version` | Patch to hash; defaults to `python/.portable_version`, then `3.14.7` |
| `-Arch` | One or more of `amd64`, `arm64`, `win32` |
| `-Mirror` | Base URL replacing `https://www.python.org/ftp/python` |
| `-SkipTclTk` | Do not fetch `tcltk.msi` for the requested arches |
| `-Workspace` | Read `python/.portable_version` from this workspace |
| `-ChecksumFile` | Write the table here instead of `scripts/checksums.psd1` |

Downloads the embeddable zip(s), matching `tcltk.msi` files, and the rolling `get-pip.py`, then rewrites `checksums.psd1` while preserving entries for other versions. Run it after a new CPython patch release or a pip update.

### `pip.ps1`

| Option | Meaning |
|---|---|
| `-UsePip` | Force `python -m pip` instead of `uv pip` |
| `-Workspace` | Consumer mode: use `python/` and `scripts/repair.py` from this directory |
| `lock` | `uv pip compile --generate-hashes --no-header` from `requirements.in`, `requirements.txt`, or `pyproject.toml` into `requirements.lock` |
| remaining args | Passed to the installer verbatim; `--user` is rejected with exit code 2 |

With `uv`: runs `uv pip <args> --python python\python.exe --system`, adding `--break-system-packages` for `install`/`sync` when the PEP 668 marker exists. Cache goes to `python/.uv_cache` (`python/.pip_cache` for pip). It maps `PIP_INDEX_URL` / `PIP_EXTRA_INDEX_URL` / `PIP_FIND_LINKS` / `PIP_NO_INDEX` to their `UV_*` equivalents. After `install`, `sync`, or `uninstall` it restores `sitecustomize.py` if a package replaced it and calls `repair.py`.

### `activate.ps1`

Dot-source only. Accepts `-Workspace <dir>` for consumer mode. Sets `PYTHONNOUSERSITE`, `VIRTUAL_ENV`, prepends `python/` and `python/Scripts/` to `PATH`, sets `TCL_LIBRARY`/`TK_LIBRARY` when `python/tcl` exists, points `JUPYTER_DATA_DIR`, `PIP_CACHE_DIR`, `UV_CACHE_DIR`, `PIP_CONFIG_FILE` inside the package, pins uv to the package interpreter (`UV_SYSTEM_PYTHON=1`, `UV_PYTHON`), maps pip mirror variables to `UV_*`, sets `PIP_FIND_LINKS`/`UV_FIND_LINKS` when `wheels/` exists, and repairs when `.portable_root` mismatches. Defines `deactivate`, which clears every variable it set.

### `build_launcher.ps1`

| Option | Meaning |
|---|---|
| `-ShimOnly` | Compile only `shim.exe` |
| `-Icon <file>` | Icon for `App.exe` |
| `-Workspace` | Consumer mode: write `App.exe` here and the shim to `<workspace>/scripts/bin` |
| `-BinDir` | Explicit shim output directory |

Uses `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (falls back to the 32-bit path). No SDK required. Output: `App.exe` ≈ 10 KB, `shim.exe` ≈ 7 KB.

### `build_release.ps1`

| Option | Meaning |
|---|---|
| `-ReleaseName` | ZIP base name; default `<folder>_Python<version>_<arch>` |
| `-Arch` | Used in the default name |
| `-AppendDateTime` | Appends `_yyyyMMdd_HHmm` |
| `-Wheelhouse` | Downloads all installed dependencies into `wheels/` and includes it |
| `-Workspace` | Consumer mode: package this directory (e.g. `.portable`) |

Requires `python/python.exe` for version detection unless `-ReleaseName` is given. Builds the shim if missing. `App.exe` is optional. Without `-Wheelhouse`, any stale `wheels/` directory is excluded from the ZIP. A workspace whose leaf starts with `.` (e.g. `.portable`) uses the parent folder name for the default ZIP name. Top-level `.bat`/`.cmd`/`.ini` entry points are included.

## Repair internals

`repair(root)`:

1. Requires `scripts/bin/shim.exe` and `python/Lib/site-packages`; otherwise returns 0.
2. Builds a map from every `*.dist-info/entry_points.txt` (`console_scripts`, `gui_scripts`).
3. Creates `shim.exe` + `.entry` for any mapped command whose `.exe` is missing (covers `pip.exe` on PBS).
4. For each `python/Scripts/*.exe`:
   - classify with `is_trampoline()` (tail contains `UV_TRAMPOLINE_KIND` / `uv.Trampoline`, or the file opens as a zip containing `__main__.py`);
   - resolve entry from metadata, else `find_entry` with a version-suffix fallback, else `entry_from_exe()` (regex over the payload's `__main__.py`);
   - copy `shim.exe` over it and write `<stem>.entry` with `module`, `func`, `gui`;
   - real binaries are skipped; already-shim files only get their `.entry` refreshed.
5. Writes the package root into `python/.portable_root`.

Triggers: `pip.ps1` after install/sync/uninstall, `activate.ps1` on dot-source, `sitecustomize.py` on interpreter start (marker mismatch) and on exit (fresh `.exe` files written by this process). The exit hook executes `repair.py` through `runpy` instead of importing it, because pip warns about new imports after an install has started. `python -S` skips both hooks.

## Environment variables

| Variable | Set by | Value / purpose |
|---|---|---|
| `PYTHONNOUSERSITE` | activate, shim | `1`; no user site-packages |
| `PIP_USER` | sitecustomize | `0`; never install into the user profile by default |
| `PIP_CACHE_DIR` | activate, sitecustomize | `python/.pip_cache` |
| `PIP_DISABLE_PIP_VERSION_CHECK` | sitecustomize | `1` |
| `PIP_CONFIG_FILE` | activate, sitecustomize | `python/pip.ini` |
| `UV_CACHE_DIR` | activate, sitecustomize | `python/.uv_cache` |
| `UV_SYSTEM_PYTHON` | activate | `1`; bare `uv pip` targets the package interpreter |
| `UV_PYTHON` | activate | absolute path to `python/python.exe` |
| `JUPYTER_DATA_DIR` | activate | `python/share/jupyter` |
| `UV_INDEX_URL` | activate, sitecustomize | mirrored from `PIP_INDEX_URL` when unset |
| `UV_EXTRA_INDEX_URL` | activate, sitecustomize | mirrored from `PIP_EXTRA_INDEX_URL` when unset |
| `PIP_FIND_LINKS` | activate, sitecustomize | `<root>/wheels` when the offline wheelhouse exists |
| `UV_FIND_LINKS` | activate, sitecustomize | same as `PIP_FIND_LINKS` when unset |

## Launcher facts (measured on this machine)

| Item | Value |
|---|---|
| pip/distlib launcher | 108,408 bytes |
| uv trampoline | 47,104 bytes |
| `shim.exe` | 7,168 bytes (varies slightly with build options) |
| `App.exe` | 10,240 bytes |
| uv payload contains | `UV_TRAMPOLINE_KIND`, `UV_PYTHON_PATH` (absolute), `__main__.py` |

## Release manifest

Included: app directories, `app.ini`, `.vscode/`, `scripts/` (including `repair.py` and `bin/shim.exe`), `python/`, `App.exe`/READMEs when present.

Rewritten: `python/Scripts/*.exe` → `shim.exe` + `.entry`; extensionless scripts → `#!..\python.exe`.

Excluded: `__pycache__`, `.pip_cache`, `.uv_cache`, `*.pyc`, `.portable_root`; `wheels/` is included only with `-Wheelhouse`.

## Known limits

- `python -S` skips the hook.
- A running executable cannot be overwritten; repair skips it and retries next start.
- Upgrading pip through `pip.exe` cannot replace the running image; use `python -m pip install -U pip`.
- Bare `uv pip install` leaves trampolines until the next interpreter start, because uv never triggers Python's exit hook.
- `pip install -e` and Jupyter `kernel.json` hold absolute paths outside `repair`'s scope.
- Unsigned `App.exe` may trigger SmartScreen when downloaded directly.
- Tools without metadata that are not trampolines cannot be converted.
