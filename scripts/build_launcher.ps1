param (
  [string]$Icon = "",
  # shim.exe is the repair payload and is always needed; App.exe is an optional
  # example of shipping an app through this environment.
  [switch]$ShimOnly,
  # Consumer mode: write App.exe into this workspace and shim into
  # <workspace>/scripts/bin instead of the upstream checkout.
  [string]$Workspace = "",
  [string]$BinDir = ""
)

$ErrorActionPreference = "Stop"

# Compiles the generic, path-relative launcher and console-script shim with the
# .NET Framework compiler shipped with Windows. No external toolchain required.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
$SourceDir = Join-Path $ScriptDir "launcher"
if ([string]::IsNullOrWhiteSpace($BinDir))
{
  $BinDir = if ([string]::IsNullOrWhiteSpace($Workspace))
  {
    Join-Path $ScriptDir "bin"
  }
  else
  {
    Join-Path $WorkspaceDir "scripts\bin"
  }
}
else
{
  $BinDir = [IO.Path]::GetFullPath($BinDir)
}
$AppExe = Join-Path $WorkspaceDir "App.exe"
$ShimExe = Join-Path $BinDir "shim.exe"

$CscCandidates = @(
  (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
  (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$Csc = $CscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-Not $Csc)
{
  Write-Host "[ERROR] .NET Framework 4 compiler (csc.exe) not found." -ForegroundColor Red
  Write-Host "        Windows 10/11 normally ships it. Install .NET Framework 4.x and retry." -ForegroundColor Red
  Exit
}

$FrameworkDir = Split-Path -Parent $Csc
$CommonArgs = @(
  "/nologo",
  "/optimize+",
  "/codepage:65001",
  "/target:exe",
  "/platform:anycpu",
  "/r:$(Join-Path $FrameworkDir 'System.dll')",
  "/r:$(Join-Path $FrameworkDir 'System.Core.dll')",
  "/r:$(Join-Path $FrameworkDir 'System.Windows.Forms.dll')"
)

if ($Icon -ne "")
{
  if (-Not (Test-Path $Icon))
  {
    Write-Host "[ERROR] Icon not found: $Icon" -ForegroundColor Red
    Exit
  }
  $CommonArgs += "/win32icon:$Icon"
}

if (-Not (Test-Path $BinDir))
{
  New-Item -ItemType Directory -Path $BinDir | Out-Null
}

Write-Host "[INFO] Compiling shim.exe ..." -ForegroundColor Cyan
& $Csc @CommonArgs "/out:$ShimExe" (Join-Path $SourceDir "Shim.cs")
if ($LASTEXITCODE -ne 0)
{
  Write-Host "[ERROR] Failed to compile Shim.cs" -ForegroundColor Red
  Exit
}

if (-Not $ShimOnly)
{
  Write-Host "[INFO] Compiling App.exe ..." -ForegroundColor Cyan
  & $Csc @CommonArgs "/out:$AppExe" (Join-Path $SourceDir "Launcher.cs")
  if ($LASTEXITCODE -ne 0)
  {
    Write-Host "[ERROR] Failed to compile Launcher.cs" -ForegroundColor Red
    Exit
  }
  Write-Host "[OK] Launcher ready: $AppExe" -ForegroundColor Green
}

Write-Host "[OK] Shim ready:     $ShimExe" -ForegroundColor Green
