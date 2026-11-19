简体中文 | [English](../en/troubleshooting.md)

# 常见问题排查

每条按"症状原文 → 根因 → 处理 → 验证"组织。先看快速定位表。

## 快速定位

| 症状 | 最可能的原因 | 章节 |
|---|---|---|
| `uv trampoline failed to canonicalize script path` | 包被移动，启动器里仍是旧绝对路径 | [1](#1-uv-trampoline-failed-to-canonicalize-script-path) |
| `error: The interpreter ... is externally managed` | PEP 668 标记未被移除，或直接用了 `python -m pip` | [2](#2-pep-668externally-managed) |
| `TclError: Can't find a usable init.tcl` | 嵌入式引擎没有 Tcl/Tk，或未设置 `TCL_LIBRARY` | [3](#3-tclerror-cant-find-a-usable-inittcl) |
| 打包时出现 `[WARN] No entry point for xxx.exe` | 该工具没有 `entry_points.txt`，也不是 trampoline | [4](#4-工具没有-entry_pointstxt) |
| 移动后 `python -c` 正常，工具却仍报错 | 启动器未被修复，或使用了 `python -S` | [5](#5-python--s-下不自动修复) |
| Jupyter 找不到内核 / 内核报路径错误 | `kernel.json` 里是旧绝对路径 | [6](#6-jupyter-内核与-editable-安装) |
| 双击 `App.exe` 被 SmartScreen 拦截 | 未签名 + 来自网络 | [7](#7-smartscreen-与杀毒软件) |
| `uv pip install` 报 `No virtual environment found` 或装到宿主机 | 未激活，uv 没锁定包内解释器 | [10](#10-uv-pip-install-装错位置或报错) |
| 工具提示找不到 `pip.exe` | launcher 被删除，或 PBS 从未提供 | [11](#11-工具提示找不到-pipexe) |
| pip 缓存或包装到了用户目录 | 未设置 `PIP_CACHE_DIR`，或用了 `--user` | [12](#12-pip-把包装到用户目录) |
| bootstrap 报 `SHA256 mismatch` | 下载内容与 `checksums.psd1` 不符，或镜像/版本错误 | [13](#13-下载校验失败sha256-mismatch) |
| 断网机器无法补装依赖 | 发布包没有带 `wheels/` | [14](#14-离线安装与锁文件) |

## 1. `uv trampoline failed to canonicalize script path`

**症状**

```text
error: uv trampoline failed to canonicalize script path
```

**根因**：pip/uv 生成的 `python/Scripts/<tool>.exe` 把安装时的解释器绝对路径写进了文件尾。目录被移动或改名后，这个路径不存在，启动器在规范化路径时就失败——此时你的 Python 代码还没开始执行。

**处理**（任选其一，都会重建 shim）：

```powershell
# 立刻修一次
python .\scripts\repair.py .

# 或激活环境（会自动检查标记）
. .\scripts\activate.ps1

# 或重新装一次该工具
.\scripts\pip.ps1 install <package>
```

**验证**

```powershell
python .\python\Scripts\<tool>.exe --help   # 应该正常输出
Get-ChildItem .\python\Scripts\<tool>.exe   # 体积应约 7 KB，而不是 47/108 KB
```

彻底避免：移动目录后先激活一次，或用 `python -m <tool>`。

## 2. PEP 668：externally managed

**症状**

```text
error: The interpreter at ... is externally managed, and indicates the following:
This Python installation is managed by uv and should not be modified.
```

**根因**：PBS 引擎自带 `EXTERNALLY-MANAGED` 标记。`bootstrap.ps1` 会删除它；若直接调用 `python -m pip` 或复用了未处理的引擎副本，标记仍可能生效。

**处理**

```powershell
# 优先使用封装脚本：它会在需要时追加 --break-system-packages
.\scripts\pip.ps1 install <package>

# 或手动删除标记（这个环境本来就由本仓库独占）
Remove-Item .\python\Lib\site-packages\EXTERNALLY-MANAGED -ErrorAction SilentlyContinue
```

**验证**：`.\scripts\pip.ps1 install <package>` 不再报错。

## 3. `TclError: Can't find a usable init.tcl`

**症状**：`import tkinter` 或 GUI 程序启动时报 `TclError`，并列出多个 `tcl8.x` 路径。

**根因**：官方嵌入式引擎不含 Tcl/Tk；且 `TCL_LIBRARY` / `TK_LIBRARY` 只在激活过 PowerShell 或经由 `App.exe` 启动时才设置，IDE 直接调用解释器时不会设置。

**处理**

```powershell
# 嵌入式引擎：补装 Tcl/Tk
.\scripts\add_tkinter.ps1

# 或者直接换成 PBS（自带 Tcl/Tk）
.\scripts\bootstrap.ps1 -Engine pbs
```

**验证**

```powershell
. .\scripts\activate.ps1
python -m tkinter
```

若只在 IDE 中失败，请在 IDE 的运行配置里补 `TCL_LIBRARY` / `TK_LIBRARY`，或改用 `python -m` 前先激活。

## 4. 工具没有 `entry_points.txt`

**症状**：`build_release.ps1` 打印 `[WARN] No entry point for xxx.exe`，移动后该工具失效。

**根因**：部分包不通过 `console_scripts` 暴露命令（老式 `scripts=`、或直接随 wheel 分发二进制）。没有元数据时无法确定入口。

**处理**

- 若该文件是 pip/uv 启动器，`repair.py` 会从它尾部的 `__main__.py` 反推 `module:func`，可以自动修复。
- 若是真实二进制（如 `ruff`、`uv`），本来就不含 Python 路径，不需要修复；打包会原样保留。
- 两者都不是时，`build_release.ps1` 会保留原文件并告警（不再静默丢弃）。

**验证**

```powershell
Get-ChildItem .\python\Scripts\*.entry   # 出问题的工具是否有 .entry
```

日常使用建议统一走 `python -m <tool>`，彻底绕开这一层。

## 5. `python -S` 下不自动修复

**症状**：移动目录后，`python -c "..."` 能跑，但启动器仍然失效；或修改 `python -S` 的启动参数后行为异常。

**根因**：`sitecustomize.py` 由 `import site` 触发，`-S` 会跳过它。同理，`site-packages` 下的 hook 都不会执行。

**处理**：用带 `site` 的方式启动，或显式修复：

```powershell
python .\scripts\repair.py .
. .\scripts\activate.ps1
```

**验证**：`Get-Content .\python\.portable_root` 的内容等于当前包根目录。

## 6. Jupyter 内核与 editable 安装

**症状**：移动目录后 Jupyter 启动内核失败，或 `import` 的自研包报 `ModuleNotFoundError`。

**根因**

- `kernel.json` 的 `argv` 记录了解释器绝对路径。虽然 `activate.ps1` 已把 `JUPYTER_DATA_DIR` 指向包内，内容仍是旧路径。
- `pip install -e` 生成的 `__editable__*.pth` 同样记录绝对路径。

**处理**

```powershell
. .\scripts\activate.ps1
python -m ipykernel install --prefix .\python --name portable --display-name "Portable Python"

# editable 安装：重新安装一次即可重写 .pth
.\scripts\pip.ps1 install -e .\my_pkg
```

**验证**

```powershell
python -m jupyter kernelspec list
Get-Content .\python\share\jupyter\kernels\*\kernel.json
```

## 7. SmartScreen 与杀毒软件

**症状**：双击 `App.exe` 提示"Windows 已保护你的电脑"；或被杀软隔离。

**根因**：`App.exe` 未签名，且来自浏览器下载的文件带 Mark-of-the-Web。

**处理**：通过 ZIP 分发（解压后通常不再提示）；确需直接分发时对 exe 签名；或在属性中解除锁定：

```powershell
Unblock-File .\App.exe
```

**验证**：双击后可正常启动，且不再出现拦截窗口。

## 8. 中文路径、超长路径

**症状**：安装或解压时报路径过长、文件找不到；偶发 `UnicodeDecodeError`。

**根因**：Windows 默认 260 字符路径上限；部分工具对非 ASCII 路径处理不一致。

**处理**：把包放在较短、纯 ASCII 的路径下（如 `D:\py`）；开启长路径支持：

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled 1
```

## 9. 看到 `[repair] N launcher(s) rebuilt`

**这是正常输出**，不是错误。它在两种情况下出现：

- 移动或复制目录后，第一次启动解释器（解压后的发布包首次运行也会如此）。
- 刚安装 / 卸载过包。

若它每次启动都出现，说明 `.portable_root` 没有写入成功（目录只读、或被安全软件拦截），检查该文件是否存在及其内容。

## 10. `uv pip install` 装错位置或报错

**症状**

```text
error: No virtual environment found; run `uv venv` to create an environment,
       or pass `--system` to install into a non-virtual environment
```

或者更隐蔽：命令成功，但 `uv pip list` 显示的是宿主机某个 Python（例如 `C:\Users\...\AppData\Roaming\uv\python\cpython-3.12...`）的包。

**根因**：uv 是独立二进制，不继承本项目的解释器选择。未激活时它会自行发现一个 Python，或在没有虚拟环境时直接报错。

**处理**

```powershell
# 方式一：激活后，UV_* 变量会把 uv 锁定到包内
. .\scripts\activate.ps1
uv pip install <package>

# 方式二：始终走封装脚本
.\scripts\pip.ps1 install <package>
```

**验证**

```powershell
uv pip list | Select-Object -First 3   # 头部应显示 Using Python ...\python
```

注意：`uv.toml` 不能解决这个问题——它的 `python` 键按当前目录解析相对路径，写绝对路径会在搬家后失效。

## 11. 工具提示找不到 `pip.exe`

**症状**：某个工具报 `FileNotFoundError: ...\python\Scripts\pip.exe`，或直接提示 `pip` 不是可执行命令。

**根因**：PBS 引擎本身不发布 `pip.exe`，它只在 `get-pip` 或 pip 自升级时出现；也可能被手工删除。

**处理**

```powershell
python .\scripts\repair.py .
```

`repair` 会按 `entry_points.txt` 为缺失的命令补建 `shim.exe` 副本与 `.entry`。

**验证**

```powershell
Get-ChildItem .\python\Scripts\pip*.exe | Select-Object Name, Length   # 约 7 KB
.\python\Scripts\pip.exe --version
```

## 12. pip 把包装到用户目录

**症状**：`pip list` 在包内看不到刚装的包；实际装进了 `%APPDATA%\Python\Python3xx\site-packages`；或 `%LOCALAPPDATA%\pip\Cache` 持续变大。

**根因**：调用了 `pip install --user`，或运行环境没有继承 `PYTHONNOUSERSITE` / `PIP_CACHE_DIR`。

**处理**

```powershell
. .\scripts\activate.ps1        # 设置 PYTHONNOUSERSITE、PIP_USER、PIP_CACHE_DIR
.\scripts\pip.ps1 install <package>
```

`sitecustomize.py` 也会为当前进程及其子进程补上这些默认值，所以从包内解释器派生的工具同样受保护。

**验证**

```powershell
python -m pip config list
python -c "import site; print(site.ENABLE_USER_SITE)"
Test-Path .\python\.pip_cache
```

## 13. 下载校验失败（SHA256 mismatch）

**症状**：bootstrap 或 `add_tkinter.ps1` 输出 `SHA256 mismatch ...` 并退出。

**根因**：下载内容与 `scripts/checksums.psd1` 记录的哈希不一致，常见于镜像内容不同步、版本/架构不匹配，或上游 `get-pip.py` 已更新。

**处理**

```powershell
# 换回官方源或可信镜像重试
.\scripts\bootstrap.ps1

# 确认镜像内容可信时覆盖哈希
.\scripts\bootstrap.ps1 -PythonSha256 <hex>
.\scripts\bootstrap.ps1 -GetPipSha256 <hex>
.\scripts\add_tkinter.ps1 -Sha256 <hex>

# 仅限可信离线文件
.\scripts\bootstrap.ps1 -SkipChecksum

# 新 patch / 新架构：刷新哈希表
.\scripts\update_checksums.ps1 -Version 3.14.10 -Arch amd64,arm64,win32
```

bootstrap 在交换前校验，失败时旧 `python/` 不会被替换；遗留的 `python.new` 可直接删除。

**验证**：`python -V` 仍指向原环境；修复源后重跑 bootstrap。

## 14. 离线安装与锁文件

**症状**：目标机断网，需要补装依赖；或两次 bootstrap 装出的依赖版本不同。

**处理**

```powershell
# 生成带哈希的锁文件；bootstrap 恢复时优先使用
.\scripts\pip.ps1 lock

# 构建带离线 wheelhouse 的发布包
.\scripts\build_release.ps1 -Wheelhouse
```

解压后的包内，`sitecustomize.py` 会自动设置 `PIP_FIND_LINKS` 与 `UV_FIND_LINKS`，因此可以：

```powershell
python -m pip install --no-index <package>
```

**验证**

```powershell
python -c "import os; print(os.environ.get('PIP_FIND_LINKS'))"   # 指向包内 wheels
Test-Path .\requirements.lock
Test-Path .\wheels
```

## 15. Consumer Mode 与脚手架

**症状 A**：生成的 `build-<app>.ps1` 报 `Submodule missing at ...`。

```powershell
git submodule update --init --recursive
```

如果是 `-SkipSubmodule` 生成的项目，先手动添加 submodule，或用 junction 指向本仓库做本地验证。

**症状 B**：`-Profile multi` 的构建长时间不结束，`.portable` 体积异常增长，目录里出现层层嵌套的 `.portable/app/.portable/...`。

旧模板会把 app 目录整体递归复制到 `<app>/.portable/app`，而 multi 的 `.portable` 就在 app 目录内部，形成自拷贝。升级脚手架后重新生成即可：

```powershell
.\scripts\new-portable-project.ps1 -Profile multi -ProjectRoot <项目> -AppDirs apps/one,apps/two -Force
```

**症状 C**：`-Profile scripts` 的项目想升级运行时。

`scripts/` 是复制进项目的实体文件，没有 submodule。重新运行脚手架并加 `-Force` 覆盖，然后重跑 `.\scripts\build.ps1`。业务代码和 `requirements.txt` 不受影响。

**验证**

```powershell
Test-Path .\scripts\build-portable.ps1          # app
Test-Path .\scripts\build.ps1                  # scripts
Test-Path .\scripts\build-all.ps1              # multi
Test-Path .\apps\one\.portable\dist            # multi 每个 app 各自产出
```

## 采集诊断信息

```powershell
python -V
python -c "import sys; print(sys.prefix); print(sys.executable)"
Get-Content .\python\.portable_root
Get-ChildItem .\python\Scripts\*.entry | Select-Object Name, Length
Get-ChildItem .\python\Lib\site-packages\*.dist-info -Directory | Measure-Object
Test-Path .\scripts\bin\shim.exe
```

把这些输出附在问题报告里，足以判断绝大多数"移动后失效"的问题。
