[English](README.md) | [简体中文](README.zh-CN.md)

# Portable Python Workspace

A fully isolated, self-bootstrapping, and zero-pollution portable Python environment for Windows. Designed for distributing standalone Python applications and maintaining reproducible development environments without relying on the host machine's Python installation.

## 🌟 Core Features

- **100% Isolated:** Strict environment variables ensure no pollution from or to the host machine's `%APPDATA%` or global Python configurations.
- **Self-Bootstrapping:** One-click script to download the Python embeddable engine, patch environment restrictions, and install `pip`.
- **Seamless IDE Integration:** Standard `site-packages` structure allows native debugging and code completion in VS Code and PyCharm with zero complex configuration.
- **Lossless Upgrades:** Safely upgrade the core Python engine while automatically exporting and restoring your dependencies.
- **Smart Launcher:** Interactive shell menus or direct passthrough execution for your application scripts.

## 📂 Directory Structure

```text
Portable_Workspace/
├── .gitignore              # Ignores the heavy /python/ directory for version control
├── README.md               # This file (English)
├── README.zh-CN.md         # Chinese documentation
├── scripts/                # The core engine scripts
│   ├── bootstrap.ps1       # Downloads engine, patches environment, installs pip
│   ├── activate.ps1        # Sources the environment into the current shell
│   ├── pip.ps1             # Isolated package manager
│   ├── run.ps1             # Universal app launcher and router
│   ├── add_tkinter.ps1     # Downloads tcl/tk for the portable Python
│   └── build_release.ps1   # Stages clean distribution, generates .bat wrappers, zips
├── python/                 # (Generated) Windows embeddable Python environment
├── dist/                   # (Generated) Release ZIP output
└── hello/                  # Example application directory
    ├── main.py
    ├── main.bat            # Direct launch wrapper (Passthrough mode)
    └── menu.bat            # Interactive launcher wrapper (Menu mode)
```

## 🚀 Getting Started

### 1. Initialize the Environment

If you just cloned this repository, the `python/` folder will be missing. Build it by running the bootstrap script:

```powershell
.\scripts\bootstrap.ps1
```

_This will download Python 3.12.14 by default (or pass `-Version <x.y.z>` for another version), extract it, enable `site-packages`, and install `pip`. If an existing environment is detected, it offers to export installed packages to `requirements.txt` first and restore them afterwards._

### 2. Install Dependencies

Use the isolated pip script to install third-party packages. They will be safely contained within the portable directory:

```powershell
.\scripts\pip.ps1 install numpy pandas jupyterlab
```

### 3. Activate for Development

To use the portable environment natively in your current terminal (for running `pytest`, `jupyter lab`, or testing scripts):

```powershell
. .\scripts\activate.ps1
```

_(Type `deactivate` to exit the environment and restore your host system's state.)_

## 🛠️ App Integration Guide

To create a new standalone application within this workspace:

1. Create a new directory (e.g., `my_app/`).
2. Write your Python scripts inside (e.g., `main.py`).
3. Create a `.bat` wrapper for end-users to click.

**For an Interactive Menu:**
_(Scans the folder and asks the user which script to run)_

```bat
@echo off
TITLE My App Launcher
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0."
```

**For Direct Execution:**
_(Runs a specific script silently without showing the menu)_

```bat
@echo off
TITLE My App
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0." -TargetScript "main.py"
```

## 📦 Building a Distributable Release

The `build_release.ps1` script creates a clean, portable ZIP ready for distribution:

1. Copies only runtime files to a staging directory (`python/`, `scripts/`, and app dirs).
2. Scans `site-packages/*.dist-info/entry_points.txt` and generates `.bat` wrappers for every `.exe` in `python/Scripts/`, replacing hardcoded-shebang binaries with relative-path batch launchers.
3. Purges caches (`__pycache__`, `.pip_cache`).
4. Zips everything into `dist/`.

```powershell
.\scripts\build_release.ps1
.\scripts\build_release.ps1 -ReleaseName "MyApp_v2"
.\scripts\build_release.ps1 -ReleaseName "MyApp" -AppendDateTime   # MyApp_20260520_1430.zip
.\scripts\build_release.ps1 -KeepStaging                           # preserve _release_staging/ for inspection
```

The generated `.bat` wrappers use `%~dp0..\python.exe` (resolved relative to the batch file), so the distribution works from any path — no reinstallation, no hardcoded paths.

## 🔄 How to Upgrade Python Versions

Never manually delete or replace the `python/` directory. Instead, use the smart bootstrapper:

1. Open `scripts\bootstrap.ps1` and change the `$Version` variable to your desired version (or pass it as a parameter: `.\scripts\bootstrap.ps1 -Version "3.13.7"`).
2. Run `.\scripts\bootstrap.ps1`.
3. The script will detect the old environment, ask if you want to export your current packages to a `requirements.txt`, replace the core engine, and then ask if you want to seamlessly restore those packages.

## 🖼️ Adding Tkinter Support

The embeddable Python does not ship with Tcl/Tk. Run the following script to download and extract the matching `tcltk` archive for your Python version:

```powershell
.\scripts\add_tkinter.ps1
```

---

### 💡 Tips for VS Code / PyCharm

Because this architecture uses the native `site-packages` mechanism, simply select `python/python.exe` as your interpreter in your IDE. All autocompletion, linting, and debugging features will work out of the box!
