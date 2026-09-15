[English](README.md) | [简体中文](README.zh-CN.md)

# 便携式 Python 工作区

一个完全隔离、自举引导、零污染的 Windows 便携式 Python 环境。专为分发独立的 Python 应用程序以及维护可复现的开发环境而设计，完全不依赖宿主机上的 Python 安装。

## 🌟 核心特性

- **100% 隔离：** 严格的环境变量控制，确保不会污染宿主机的 `%APPDATA%` 或全局 Python 配置，也不会被其污染。
- **自举引导：** 一键脚本即可下载 Python 嵌入式引擎、修补环境限制并安装 `pip`。
- **无缝 IDE 集成：** 标准的 `site-packages` 目录结构，让 VS Code 和 PyCharm 无需任何复杂配置即可原生支持调试与代码补全。
- **无损升级：** 安全升级 Python 核心引擎，同时自动导出并还原您的依赖包。
- **智能启动器：** 为应用脚本提供交互式菜单或直接透传执行两种模式。

## 📂 目录结构

```text
Portable_Workspace/
├── .gitignore              # 将庞大的 /python/ 目录排除在版本控制之外
├── README.md               # 英文文档
├── README.zh-CN.md         # 本文件（中文文档）
├── scripts/                # 核心引擎脚本
│   ├── bootstrap.ps1       # 下载引擎、修补环境、安装 pip
│   ├── activate.ps1        # 将环境注入当前 Shell
│   ├── pip.ps1             # 隔离的包管理器
│   ├── run.ps1             # 通用应用启动器与路由
│   ├── add_tkinter.ps1     # 为便携版 Python 下载 tcl/tk
│   └── build_release.ps1   # 构建干净的发行版，生成 .bat 包装器并打包 ZIP
├── python/                 # （自动生成）Windows 嵌入式 Python 环境
├── dist/                   # （自动生成）发行版 ZIP 输出目录
└── hello/                  # 示例应用目录
    ├── main.py
    ├── main.bat            # 直接启动包装器（透传模式）
    └── menu.bat            # 交互式启动包装器（菜单模式）
```

## 🚀 快速开始

### 1. 初始化环境

如果您刚克隆本仓库，`python/` 目录尚不存在。运行引导脚本即可构建：

```powershell
.\scripts\bootstrap.ps1
```

_脚本默认下载 Python 3.14.7（也可通过 `-Version <x.y.z>` 指定其他版本），解压后启用 `site-packages`，并安装 `pip`、`setuptools` 和 `wheel`。如果检测到已有环境，会先询问是否将已安装的包导出到 `requirements.txt`，完成后可自动还原。_

### 2. 安装依赖

使用隔离的 pip 脚本安装第三方包。所有包都会被安全地限制在便携目录内：

```powershell
.\scripts\pip.ps1 install numpy pandas jupyterlab
```

### 3. 激活开发环境

若要在当前终端中原生使用便携环境（运行 `pytest`、`jupyter lab` 或测试脚本）：

```powershell
. .\scripts\activate.ps1
```

_（输入 `deactivate` 即可退出环境并恢复宿主机的原有状态。）_

## 🛠️ 应用集成指南

在此工作区中创建新的独立应用：

1. 新建一个目录（例如 `my_app/`）。
2. 在其中编写 Python 脚本（例如 `main.py`）。
3. 为最终用户创建一个可双击的 `.bat` 包装器。

**交互式菜单模式：**
_（扫描目录并让用户选择要运行的脚本）_

```bat
@echo off
TITLE My App Launcher
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0."
```

**直接执行模式：**
_（静默运行指定脚本，不显示菜单）_

```bat
@echo off
TITLE My App
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0." -TargetScript "main.py"
```

## 📦 构建可分发的发行版

`build_release.ps1` 脚本会创建干净、可移植的发行版 ZIP：

1. 仅将运行时文件复制到暂存目录（`python/`、`scripts/` 及各应用目录）。
2. 扫描 `site-packages/*.dist-info/entry_points.txt`，为 `python/Scripts/` 下的每个 `.exe` 生成 `.bat` 包装器，用相对路径的批处理启动器替换硬编码 shebang 的二进制文件。
3. 清除缓存（`__pycache__`、`.pip_cache`）。
4. 将所有内容打包为 `dist/` 下的 ZIP。

```powershell
.\scripts\build_release.ps1
.\scripts\build_release.ps1 -ReleaseName "MyApp_v2"
.\scripts\build_release.ps1 -ReleaseName "MyApp" -AppendDateTime   # MyApp_20260520_1430.zip
.\scripts\build_release.ps1 -KeepStaging                           # 保留 _release_staging/ 以便检查
```

生成的 `.bat` 包装器使用 `%~dp0..\python.exe`（相对于批处理文件解析），因此发行版可以在任意路径下运行——无需重新安装，没有硬编码路径。

## 🔄 如何升级 Python 版本

切勿手动删除或替换 `python/` 目录。请使用智能引导脚本：

1. 打开 `scripts\bootstrap.ps1`，将 `$Version` 变量改为目标版本（或直接传参：`.\scripts\bootstrap.ps1 -Version "3.13.7"`）。
2. 运行 `.\scripts\bootstrap.ps1`。
3. 脚本会检测旧环境，询问是否将当前包导出为 `requirements.txt`，替换核心引擎后，再询问是否无缝还原这些包。

## 🖼️ 添加 Tkinter 支持

嵌入式 Python 不自带 Tcl/Tk。运行以下脚本即可下载并解压与当前 Python 版本匹配的 `tcltk` 组件：

```powershell
.\scripts\add_tkinter.ps1
```

---

### 💡 VS Code / PyCharm 使用技巧

由于本架构使用原生 `site-packages` 机制，只需在 IDE 中将 `python/python.exe` 选为解释器即可。所有自动补全、代码检查和调试功能均可开箱即用！
