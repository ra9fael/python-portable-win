简体中文 | [English](README.en.md)

# 便携式 Python 工作区

一个完全隔离、自举引导、零污染的 Windows 便携式 Python 环境：**整个目录拷到任意路径、任意机器，都能继续开发和运行**。不依赖宿主机的 Python，也不往 `%APPDATA%` 写任何东西。

## 心智模型

- **一个目录 = 一个解释器 + 平铺的 `site-packages`**，不使用 venv。
- **入口就是 `python.exe`**：激活 Shell，或让 IDE 指向 `python/python.exe`。
- **唯一会失效的是"记录过绝对路径的产物"**——pip/uv 生成的启动器。它们由 `repair.py` 自动换壳，不需要你手动处理。

## 核心特性

- **100% 隔离：** 严格的环境变量控制，不污染宿主机 `%APPDATA%`，也不被其污染。
- **自举引导：** 一键脚本安装完整 Python 引擎（有 `uv` 时用 python-build-standalone，否则回退官方嵌入式包）。
- **不需要 `.bat`：** 入口是解释器本身；依赖包生成的启动器被换成相对路径 shim，包被移动后自动修复。
- **自动换壳：** 安装后、激活时、任意解释器启动时，三处都会检查并修复失效启动器。
- **无缝 IDE 集成：** 标准 `site-packages` + `${workspaceFolder}` 配置，换路径不用改设置。
- **无损升级：** 升级引擎前自动导出依赖，升级后可一键还原。
- **可选分发模板：** `App.exe` 演示如何把应用打包进这套环境，开发时并非必需。

## 快速开始

### 1. 初始化环境

```powershell
.\scripts\bootstrap.ps1
```

`uv` 在 `PATH` 中时安装 python-build-standalone（完整 stdlib、自带 Tcl/Tk、无需补 `._pth`），并移除 PEP 668 标记；否则回退官方嵌入式包。可用 `-Engine pbs` / `-Engine embeddable` 强制指定，默认 Python 3.14.7（`-Version` 可改）。若检测到旧环境，会先询问是否导出 `requirements.txt`。

下载默认按 `scripts/checksums.psd1` 校验 SHA256；不匹配会中止且保留旧环境。可用 `-PythonSha256` / `-GetPipSha256` 覆盖，或用 `-SkipChecksum` 跳过。升级到新 patch 或需要其他架构时，先运行 `.\scripts\update_checksums.ps1 -Version <x.y.z> -Arch amd64,arm64,win32` 刷新哈希。国内网络可用 `-Mirror <引擎镜像前缀>`（PBS 传给 `uv --mirror`，embeddable 替换下载前缀），包索引用 `-PipIndexUrl`（同时导出为 `PIP_INDEX_URL` / `UV_INDEX_URL`）。CI 或无交互环境加 `-NonInteractive`。

### 2. 安装依赖

```powershell
.\scripts\pip.ps1 install numpy pandas jupyterlab
```

检测到 `uv` 时走 `uv pip ... --system`（更快、缓存留在包内），否则回退 `python -m pip`。装完会立刻把生成的 `.exe` 换成相对路径 shim；如果第三方包自带的 `sitecustomize.py` 覆盖了项目钩子，会自动恢复。`--user` 会被拒绝。

需要可复现还原时，生成带哈希的锁文件：

```powershell
.\scripts\pip.ps1 lock     # requirements.in / requirements.txt / pyproject.toml -> requirements.lock
```

`bootstrap.ps1` 在恢复依赖时优先使用 `requirements.lock`，没有锁文件才回退 `requirements.txt`。

### 3. 激活并运行

```powershell
. .\scripts\activate.ps1
python -m jupyter lab      # 或 python main.py / pytest / ruff
```

激活会设置 `PYTHONNOUSERSITE`，把 `python/` 与 `python/Scripts/` 加入 `PATH`，指向包内 Tcl/Tk，把 pip/uv 缓存与 `JUPYTER_DATA_DIR` 收进包内，并在包被移动后自动修复失效启动器。`deactivate` 可完全还原。

> 用 `python -m <工具>` 而不是直接调用 `Scripts\<工具>.exe`，可以完全绕过启动器这一层。

### 4.（可选）通过 `App.exe` 运行

```powershell
.\scripts\bootstrap.ps1 -WithLauncher
.\App.exe
```

约 10 KB 的启动器会读取 `app.ini`、相对自身解析 `python\python.exe`、设置环境变量后启动配置的模块。它是"如何在这套环境上分发应用"的示例，不是开发所必需的。

## 日常任务速查

| 任务 | 命令 |
|---|---|
| 激活环境 | `. .\scripts\activate.ps1` |
| 安装依赖 | `.\scripts\pip.ps1 install <包名>` |
| 卸载依赖 | `.\scripts\pip.ps1 uninstall <包名>` |
| 生成锁文件 | `.\scripts\pip.ps1 lock` |
| 用 uv 安装（需先激活） | `. .\scripts\activate.ps1; uv pip install <包名>` |
| 运行脚本 | `python path\to\script.py` |
| 运行模块/工具 | `python -m <module>` |
| 跑测试 | `python -m pytest` |
| 重建 shim（修复载荷） | `.\scripts\build_launcher.ps1 -ShimOnly` |
| 构建发布包 | `.\scripts\build_release.ps1` |
| 构建带离线 wheelhouse 的发布包 | `.\scripts\build_release.ps1 -Wheelhouse` |
| 自测搬迁与修复逻辑 | `.\scripts\selftest.ps1` |
| 升级 Python | 改 `$Version` 后重跑 `bootstrap.ps1` |
| 给嵌入式引擎加 Tkinter | `.\scripts\add_tkinter.ps1` |
| 生成单应用脚手架 | `.\scripts\new-portable-project.ps1 -ProjectRoot <项目> -AppDir app` |
| 生成个人脚本环境 | `.\scripts\new-portable-project.ps1 -Profile scripts -ProjectRoot <项目> -AppDir my_tools` |
| 生成一仓多 app 脚手架 | `.\scripts\new-portable-project.ps1 -Profile multi -ProjectRoot <项目> -AppDirs apps/one,apps/two` |

## 目录结构

```text
Portable_Workspace/
├── README.md               # 本文件（中文，默认）
├── README.en.md            # English
├── AGENTS.md               # 面向 AI agent 的仓库约定
├── app.ini                 # 可选：App.exe 配置（module / gui / app_dir）
├── App.exe                 # （可选）启动器示例，用 -WithLauncher 构建
├── .vscode/settings.json   # VS Code 便携解释器路径
├── docs/
│   ├── zh/                 # 架构与原理、常见问题排查
│   └── en/
├── skills/
│   └── portable-python-env/  # 给 agent 用的操作手册（SKILL.md）
├── scripts/                # 核心引擎脚本
│   ├── bootstrap.ps1       # 引擎 + pip + 启动钩子 + shim
│   ├── activate.ps1        # 将环境注入当前 Shell，并检查修复
│   ├── pip.ps1             # 隔离包管理器，装完自动重建 shim
│   ├── run.ps1             # 可选的开发用脚本菜单
│   ├── add_tkinter.ps1     # 为嵌入式引擎补充 tcl/tk
│   ├── checksum.ps1        # SHA256 校验辅助函数
│   ├── checksums.psd1      # 下载产物哈希表
│   ├── update_checksums.ps1 # 刷新版本/架构哈希
│   ├── new-portable-project.ps1 # 为新项目生成脚手架（app/scripts/multi）
│   ├── workspace.ps1       # 解析 -Workspace，暂存运行时脚本
│   ├── build_launcher.ps1  # 用 csc.exe 编译 shim.exe（默认不再编译 App.exe）
│   ├── repair.py           # 可被 import：为当前位置重建命令行工具 shim
│   ├── sitecustomize.py    # 复制进 site-packages，解释器启动时检查
│   ├── build_release.ps1   # 流式构建发行版 ZIP
│   └── launcher/           # Launcher.cs / Shim.cs 源码
├── templates/              # 新项目脚手架模板（consumer/ 与 scripts/）
├── python/                 # （生成，git-ignored）可搬迁的 Python 环境
├── dist/                   # （生成）发行版 ZIP 输出
└── hello/                  # 示例应用（main.py / hello_tk.py）
```

## 工作原理（摘要）

`python.exe` 从自身位置推导 `sys.prefix`，所以解释器和 `site-packages` 天然可搬。会随路径失效的只有 pip/uv 生成的**启动器**——它们在 exe 尾部写死了安装时的绝对路径。

本项目的处理方式是：用 `scripts/bin/shim.exe`（约 7 KB、不含任何路径）替换这些启动器，身份信息放在同名的 `<name>.entry` 文本里，运行时由 shim 按自身位置反推解释器。没有 launcher 也能触发修复：`pip.ps1` 安装后、`activate.ps1` 激活时、`sitecustomize.py` 在解释器启动与退出时都会检查。

激活后 `uv pip install` 也会被 `UV_*` 变量锁定到包内解释器；`sitecustomize.py` 还会把包内 `Scripts` 追加进子进程的 `PATH`，并固定 `PIP_USER` / `PIP_CACHE_DIR`，因此直接调用 `pip.exe` 的工具也不会装到用户目录。

完整原理、入口形态对比和边界见 [架构与工作原理](docs/zh/architecture.md)。也可以看可交互的 [HTML 教程](tutorial/portable-python-tutorial.html)（中文，页面内可切换英文；[在线版](https://ra9fael.github.io/python-portable-win/)）。

## 作为共享运行时（Consumer Mode）

新项目推荐先生成脚手架。先从本仓库的克隆里运行：

```powershell
git clone https://github.com/ra9fael/python-portable-win.git C:\tools\python-portable-win
C:\tools\python-portable-win\scripts\new-portable-project.ps1 `
  -ProjectRoot D:\dev\github\my-app `
  -AppDir app `
  -Requirements requirements.txt `
  -PythonVersion 3.12.10
```

它会：添加并 pin `vendor/python-portable-win` submodule、生成 `scripts/build-portable.ps1`、把 `.portable/` 写进 `.gitignore`。之后：

```powershell
cd D:\dev\github\my-app
# 按需修改 scripts/build-portable.ps1 的 stage/TODO 部分
.\scripts\build-portable.ps1
```

如果项目已经有 submodule，也可以直接用：

```powershell
.\vendor\python-portable-win\scripts\new-portable-project.ps1 -ProjectRoot . -AppDir app -Requirements requirements.txt
```

脚手架按项目形态提供三种 profile：

| Profile | 适用场景 | 生成物 |
|---|---|---|
| `app`（默认） | 单个应用 | submodule + `scripts/build-portable.ps1` + `.portable/` |
| `scripts` | 个人便携脚本环境 | 复制上游 `scripts/`，不添加 submodule，代码放 `my_tools/` |
| `multi` | 一仓多 app | submodule + 每个 app 一个 `scripts/build-<app>.ps1` + `build-all.ps1` |

```powershell
# 个人脚本环境：scripts/ 是仓库里的实体文件，没有 submodule
.\scripts\new-portable-project.ps1 -Profile scripts -ProjectRoot D:\dev\my-tools -AppDir my_tools

# 一仓多 app：每个 app 拥有自己的 <app>/.portable
.\scripts\new-portable-project.ps1 -Profile multi -ProjectRoot D:\dev\my-suite `
  -AppDirs apps/one,apps/two
```

`multi` 的 `-Workspace` 是相对每个 app 的路径（默认 `.portable`），生成的 `build-all.ps1` 会串行构建全部 app。

手动接入的等价命令：

```powershell
git submodule add https://github.com/ra9fael/python-portable-win.git vendor/python-portable-win
New-Item -ItemType Directory .portable

.\vendor\python-portable-win\scripts\bootstrap.ps1 -Workspace .\.portable -Engine embeddable -Version 3.12.10
.\vendor\python-portable-win\scripts\pip.ps1 -Workspace .\.portable install -r requirements.txt
.\vendor\python-portable-win\scripts\build_release.ps1 -Workspace .\.portable
```

约定：

- `.portable/` 是纯生成物，加入项目 `.gitignore`；不要把 `-Workspace` 指向仓库根目录，否则运行时的 `scripts/` 会和业务脚本混在一起。
- `-Workspace` 会把 `python/`、`scripts/repair.py`、`scripts/sitecustomize.py`、`scripts/bin/shim.exe` 和 `dist/` 都放在该目录。
- 需要特定 Python 版本时用 `-Version`；项目自己的校验表这样生成：

```powershell
.\vendor\python-portable-win\scripts\update_checksums.ps1 `
  -Workspace .\.portable -ChecksumFile .\.portable\checksums.psd1 -Version 3.12.10
.\vendor\python-portable-win\scripts\bootstrap.ps1 `
  -Workspace .\.portable -Engine embeddable -Version 3.12.10 `
  -ChecksumFile .\.portable\checksums.psd1
```

- 升级上游只需 bump submodule 的 commit，然后重新构建；不带 `-Workspace` 的默认行为保持不变。
- 项目特定的原生 DLL（例如 `msvcp140.dll`）仍由项目自己的构建脚本补到 `.portable\python\`，不放进上游仓库。
- 分发编译产物（Cython `.pyd`、Nuitka 输出等）属于应用构建层，不放进本仓库。把它们放到 stage 后的 `<workspace>/app` 即可随包分发；本仓库不提供编译或加密能力。编译所用的 Python 必须与随包引擎同小版本、同架构；随包引擎是 embeddable 时它不带头文件，需要在开发者环境用同版本 CPython 编译并在包内验证 `import`。发布包里不要同时保留被保护模块的 `.py`。

## 分发应用

1. 新建应用目录（如 `my_app/`），写入 `main.py`。
2. 按需配置 `app.ini`：

```ini
[app]
module = my_app.main
gui = false
# app_dir = my_app   # 可选的额外 PYTHONPATH 目录
```

3. 用 `python -m my_app.main` 运行；构建了启动器后也可直接双击 `App.exe`。

`gui = true` 会用 `pythonw.exe` 启动（无控制台窗口）。临时覆盖入口：

```powershell
.\App.exe --module my_app.gui
.\App.exe --script my_app\main.py -- --verbose
```

### 构建发布包

```powershell
.\scripts\build_release.ps1                                        # 按目录名 + Python 版本 + 架构自动命名
.\scripts\build_release.ps1 -ReleaseName "MyApp_v2"                # MyApp_v2.zip
.\scripts\build_release.ps1 -ReleaseName "MyApp" -AppendDateTime   # MyApp_20260520_1430.zip
.\scripts\build_release.ps1 -Wheelhouse                            # 附带离线 wheels/
```

`-Wheelhouse` 会把当前已安装依赖（含依赖树）下载到 `wheels/` 并打进 ZIP。目标机器断网时，`sitecustomize` 会自动设置 `PIP_FIND_LINKS`，直接 `python -m pip install --no-index <包名>` 即可补装。

打包过程会：

1. 直接流式写入 ZIP（`python/`、`scripts/`、`app.ini`、`.vscode/`、应用目录，`App.exe` 存在时一并），无需 staging 拷贝。
2. 按内容识别启动器，把 `python/Scripts/` 下的 exe 换成 `shim.exe` + `<name>.entry`；真实编译的二进制（如 `ruff`）原样保留。
3. 改写无后缀脚本的 shebang（如 `numba`、`jsonpointer`）。
4. 排除缓存（`__pycache__`、`.pip_cache`、`.uv_cache`、`.portable_root`）；未指定 `-Wheelhouse` 时不包含 `wheels/`。

## 升级 Python 版本

不要手动删除或替换 `python/`：

1. 修改 `scripts\bootstrap.ps1` 的 `$Version`，或直接传参 `.\scripts\bootstrap.ps1 -Version "3.13.7"`。
2. 运行脚本。检测到旧环境时会询问是否导出 `requirements.txt`，替换引擎后再询问是否还原依赖。

安装成功后实际 patch 版本会写入 `python/.portable_version`；下次不带 `-Version` 运行时会沿用该版本，避免“3.14”这类浮动版本在不同时间装出不同结果。

## 添加 Tkinter 支持

PBS 引擎自带 Tcl/Tk；嵌入式引擎没有：

```powershell
.\scripts\add_tkinter.ps1
```

下载默认按 `scripts/checksums.psd1` 校验；可用 `-Sha256` 覆盖或 `-SkipChecksum` 跳过，镜像用 `-Mirror`。如果检测到已有 Tcl/Tk（PBS 或之前已补装）会直接跳过，需要重装时加 `-Force`。`activate.ps1` 会自动设置 `TCL_LIBRARY`/`TK_LIBRARY`；`sitecustomize` 和 `App.exe` 在未激活时也会设置。

## 文档

| 文档 | 内容 |
|---|---|
| [架构与工作原理](docs/zh/architecture.md) | 三层路径、入口形态、shim 机制、三条修复触发、能力边界 |
| [常见问题排查](docs/zh/troubleshooting.md) | 症状 → 根因 → 处理 → 验证 |
| [SKILL.md](skills/portable-python-env/SKILL.md) | 给 agent 的操作手册：触发条件、不变量、任务配方 |

## IDE 提示

在 VS Code / PyCharm 中把 `python/python.exe` 选为解释器即可。仓库内置的 `.vscode/settings.json` 使用 `${workspaceFolder}`，工作区移动后依然有效，补全、检查、调试开箱即用。
