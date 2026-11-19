param (
  [switch]$Keep
)

$ErrorActionPreference = "Stop"

# Exercises the relocation machinery against a throwaway copy of python/:
# startup repair, launcher recreation, trampoline conversion and a real move.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$SourcePython = Join-Path $WorkspaceDir "python"
$SourceShim = Join-Path $ScriptDir "bin\shim.exe"

if (-not (Test-Path (Join-Path $SourcePython "python.exe"))) {
  Write-Host "[ERROR] python\python.exe not found - run bootstrap.ps1 first." -ForegroundColor Red
  Exit 1
}
if (-not (Test-Path $SourceShim)) {
  Write-Host "[ERROR] scripts\bin\shim.exe not found - run build_launcher.ps1 -ShimOnly first." -ForegroundColor Red
  Exit 1
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("portable-selftest-" + $PID)
if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force }

$Failures = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) {
    Write-Host "[PASS] $Name" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] $Name  $Detail" -ForegroundColor Red
    $script:Failures++
  }
}

Write-Host ">>> Preparing test tree at $TempRoot" -ForegroundColor Cyan
Check "test path is ASCII and short" ($TempRoot.Length -le 150 -and $TempRoot -notmatch "[^\x00-\x7F]") $TempRoot
New-Item -ItemType Directory -Force (Join-Path $TempRoot "scripts\bin") | Out-Null
Copy-Item $SourcePython (Join-Path $TempRoot "python") -Recurse -Force
Copy-Item (Join-Path $ScriptDir "repair.py"), (Join-Path $ScriptDir "sitecustomize.py") (Join-Path $TempRoot "scripts")
Copy-Item $SourceShim (Join-Path $TempRoot "scripts\bin")

$TestPython = Join-Path $TempRoot "python\python.exe"
$ScriptsDir = Join-Path $TempRoot "python\Scripts"
Copy-Item (Join-Path $ScriptDir "sitecustomize.py") (Join-Path $TempRoot "python\Lib\site-packages\sitecustomize.py") -Force
Set-Content (Join-Path $TempRoot "python\pip.ini") "[global]`nuser = false`ndisable-pip-version-check = true`n" -Encoding ASCII
Remove-Item (Join-Path $TempRoot "python\.portable_root") -Force -ErrorAction SilentlyContinue

# 1. First start must repair and write the marker
$output = & $TestPython -c "print('boot-ok')" 2>&1 | Out-String
Check "first start runs" ($output -match "boot-ok") $output
Check "marker written" (Test-Path (Join-Path $TempRoot "python\.portable_root"))

# 2. A deleted launcher is recreated from metadata
Remove-Item (Join-Path $ScriptsDir "pip.exe") -Force
& $TestPython (Join-Path $TempRoot "scripts\repair.py") $TempRoot | Out-Null
$pipExe = Join-Path $ScriptsDir "pip.exe"
$shimSize = (Get-Item $SourceShim).Length
Check "pip.exe recreated" ((Test-Path $pipExe) -and ((Get-Item $pipExe).Length -eq $shimSize))

# 2b. A package-provided sitecustomize.py is replaced by the project hook
Set-Content (Join-Path $TempRoot "python\Lib\site-packages\sitecustomize.py") "# third-party`n" -Encoding ASCII
& $TestPython (Join-Path $TempRoot "scripts\repair.py") $TempRoot | Out-Null
$installedHook = Get-Content (Join-Path $TempRoot "python\Lib\site-packages\sitecustomize.py") -Raw
$sourceHook = Get-Content (Join-Path $ScriptDir "sitecustomize.py") -Raw
Check "sitecustomize restored" ($installedHook -eq $sourceHook)

# 3. A trampoline without dist-info is converted from its own payload
$tool = @'
def main():
    print("SELFTEST-TOOL-OK")
    return 0
'@
Set-Content (Join-Path $TempRoot "python\Lib\site-packages\_selftest_tool.py") $tool -Encoding UTF8

Add-Type -AssemblyName System.IO.Compression
$zipPath = Join-Path $TempRoot "payload.zip"
$zipStream = [IO.File]::Create($zipPath)
$archive = New-Object IO.Compression.ZipArchive($zipStream, [IO.Compression.ZipArchiveMode]::Create)
$entry = $archive.CreateEntry("__main__.py")
$writer = New-Object IO.StreamWriter($entry.Open())
$writer.Write("from _selftest_tool import main`n")
$writer.Dispose()
$archive.Dispose()
$zipStream.Dispose()

$fakeExe = Join-Path $ScriptsDir "faketool.exe"
$stub = [IO.File]::ReadAllBytes($pipExe)
$payload = [IO.File]::ReadAllBytes($zipPath)
[IO.File]::WriteAllBytes($fakeExe, $stub + $payload)
Remove-Item $zipPath -Force

& $TestPython (Join-Path $TempRoot "scripts\repair.py") $TempRoot | Out-Null
$entryFile = Join-Path $ScriptsDir "faketool.entry"
Check "trampoline converted" ((Get-Item $fakeExe).Length -eq $shimSize)
Check "entry recovered from payload" ((Test-Path $entryFile) -and ((Get-Content $entryFile -Raw) -match "_selftest_tool"))

$toolOutput = & $fakeExe 2>&1 | Out-String
Check "converted tool runs" ($toolOutput -match "SELFTEST-TOOL-OK") $toolOutput

# 4. The whole tree still works after a move
$MovedRoot = "$TempRoot-moved"
Rename-Item $TempRoot $MovedRoot
$movedOutput = & (Join-Path $MovedRoot "python\Scripts\pip.exe") --version 2>&1 | Out-String
Check "tool works after move" ($movedOutput -match "pip ") $movedOutput

if ($Keep) {
  Write-Host ">>> Kept test tree at $MovedRoot" -ForegroundColor DarkGray
} else {
  Remove-Item $MovedRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Failures -gt 0) {
  Write-Host "`n$Failures check(s) failed." -ForegroundColor Red
  Exit 1
}
Write-Host "`nAll checks passed." -ForegroundColor Green
Exit 0
