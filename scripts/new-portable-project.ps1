param (
  [Parameter(Mandatory = $true)]
  [string]$ProjectRoot,
  [ValidateSet("app", "scripts", "multi")]
  [string]$Profile = "app",
  # app/scripts: source directory. multi: use -AppDirs.
  [string]$AppDir = "",
  [string[]]$AppDirs = @(),
  [string]$Requirements = "",
  [string]$PythonVersion = "3.14.7",
  [string]$Workspace = ".portable",
  [string]$SubmodulePath = "vendor/python-portable-win",
  [string]$UpstreamUrl = "https://github.com/ra9fael/python-portable-win.git",
  # Tag/commit to pin the submodule to. Defaults to this checkout's tag or SHA.
  [string]$Ref = "",
  [switch]$SkipSubmodule,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UpstreamRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$TemplateApp = Join-Path $UpstreamRoot "templates\consumer\build-portable.ps1"
$TemplateScriptsBuild = Join-Path $UpstreamRoot "templates\scripts\build.ps1"
$TemplateScriptsStart = Join-Path $UpstreamRoot "templates\scripts\start.bat"
$TemplateScriptsMain = Join-Path $UpstreamRoot "templates\scripts\main.py"

foreach ($Template in @($TemplateApp, $TemplateScriptsBuild, $TemplateScriptsStart, $TemplateScriptsMain)) {
  if (-not (Test-Path $Template)) { throw "Template not found: $Template" }
}

if (-not (Test-Path $ProjectRoot)) {
  New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

$Commit = (& git -C $UpstreamRoot rev-parse HEAD 2>$null | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($Commit)) { $Commit = "unknown" }

function Add-IgnoreEntry {
  param([string]$ProjectRoot, [string]$Entry)

  $Gitignore = Join-Path $ProjectRoot ".gitignore"
  $Lines = if (Test-Path $Gitignore) { @(Get-Content $Gitignore) } else { @() }
  if (-not ($Lines | Where-Object { $_.Trim() -eq $Entry })) {
    Add-Content -Path $Gitignore -Value $Entry -Encoding ASCII
  }
}

function Write-Template {
  param(
    [string]$Template,
    [string]$Destination,
    [hashtable]$Replacements,
    [switch]$Force
  )

  if ((Test-Path $Destination) -and -not $Force) {
    throw "$Destination already exists; use -Force to overwrite."
  }
  $Content = Get-Content $Template -Raw
  foreach ($Key in $Replacements.Keys) {
    $Content = $Content.Replace($Key, [string]$Replacements[$Key])
  }
  if ($Content -cmatch '__[A-Z][A-Z0-9_]*__') {
    throw "Unreplaced template token in ${Template}: $($Matches[0])"
  }
  New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
  $Encoding = if ($Destination.EndsWith(".bat")) { "ASCII" } else { "UTF8" }
  Set-Content -Path $Destination -Value $Content -Encoding $Encoding
}

function Add-PortableSubmodule {
  param(
    [string]$ProjectRoot,
    [string]$SubmodulePath,
    [string]$UpstreamUrl,
    [string]$UpstreamRoot,
    [string]$Ref,
    [switch]$Skip
  )

  if ($Skip) { return }
  if (-not (Test-Path (Join-Path $ProjectRoot ".git"))) {
    Write-Host "[WARN] $ProjectRoot is not a git repository; skipping submodule add." -ForegroundColor Yellow
    return
  }

  $Target = Join-Path $ProjectRoot $SubmodulePath
  if (-not (Test-Path $Target)) {
    & git -C $ProjectRoot submodule add $UpstreamUrl $SubmodulePath
    if ($LASTEXITCODE -ne 0) { throw "git submodule add failed (exit $LASTEXITCODE)" }
  }
  else {
    Write-Host "[OK] Submodule already present: $Target" -ForegroundColor Green
  }

  if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = (& git -C $UpstreamRoot describe --tags --exact-match HEAD 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($Ref)) {
      $Ref = (& git -C $UpstreamRoot rev-parse HEAD 2>$null).Trim()
    }
  }
  if ([string]::IsNullOrWhiteSpace($Ref)) {
    Write-Host "[WARN] Could not detect a tag/SHA; the submodule will follow its default branch." -ForegroundColor Yellow
  }
  else {
    & git -C $Target checkout $Ref
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Ref failed in $Target" }
    Write-Host "[OK] Pinned submodule to $Ref" -ForegroundColor Green
  }
}

function Assert-RelativePath {
  param([string]$Path, [string]$Name)

  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Name is required." }
  if ([IO.Path]::IsPathRooted($Path)) { throw "$Name must be relative to the project root." }
  if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "$Name must not escape the project root." }
}

switch ($Profile) {
  "app" {
    if ([string]::IsNullOrWhiteSpace($AppDir)) { $AppDir = "app" }
    if ([string]::IsNullOrWhiteSpace($Requirements)) { $Requirements = "requirements.txt" }
    Assert-RelativePath $AppDir "-AppDir"
    Assert-RelativePath $Requirements "-Requirements"

    Add-PortableSubmodule -ProjectRoot $ProjectRoot -SubmodulePath $SubmodulePath `
      -UpstreamUrl $UpstreamUrl -UpstreamRoot $UpstreamRoot -Ref $Ref -Skip:$SkipSubmodule

    Write-Template -Template $TemplateApp -Destination (Join-Path $ProjectRoot "scripts\build-portable.ps1") -Replacements @{
      "__APP_DIR__" = ($AppDir -replace '/', '\')
      "__REQUIREMENTS__" = ($Requirements -replace '/', '\')
      "__PYTHON_VERSION__" = $PythonVersion
      "__WORKSPACE__" = $Workspace
      "__SUBMODULE_PATH__" = ($SubmodulePath -replace '/', '\')
    } -Force:$Force

    Add-IgnoreEntry $ProjectRoot "$($Workspace.TrimEnd('/'))/"

    foreach ($Path in @($AppDir, $Requirements)) {
      if (-not (Test-Path (Join-Path $ProjectRoot $Path))) {
        Write-Host "[WARN] Missing $Path; create it before running build-portable.ps1." -ForegroundColor Yellow
      }
    }

    Write-Host "`n[OK] Created $(Join-Path $ProjectRoot 'scripts\build-portable.ps1')" -ForegroundColor Green
    Write-Host "     1. Review the stage/TODO section." -ForegroundColor Gray
    Write-Host "     2. Run: .\scripts\build-portable.ps1" -ForegroundColor Gray
    break
  }

  "scripts" {
    if ([string]::IsNullOrWhiteSpace($AppDir)) { $AppDir = "my_tools" }
    if ([string]::IsNullOrWhiteSpace($Requirements)) { $Requirements = "requirements.txt" }
    Assert-RelativePath $AppDir "-AppDir"
    Assert-RelativePath $Requirements "-Requirements"

    $DestScripts = Join-Path $ProjectRoot "scripts"
    if (Test-Path $DestScripts) {
      if (-not $Force) { throw "$DestScripts already exists; use -Force to replace the copied tooling." }
      Remove-Item $DestScripts -Recurse -Force
    }
    Copy-Item (Join-Path $UpstreamRoot "scripts") $DestScripts -Recurse -Force
    Remove-Item (Join-Path $DestScripts "bin") -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $DestScripts -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $Module = (($AppDir -replace '[\\/]', '.') + ".main")
    $AppName = Split-Path $AppDir -Leaf

    Write-Template -Template $TemplateScriptsBuild -Destination (Join-Path $DestScripts "build.ps1") -Replacements @{
      "__PYTHON_VERSION__" = $PythonVersion
      "__REQUIREMENTS__" = ($Requirements -replace '/', '\')
      "__UPSTREAM_COMMIT__" = $Commit
      "__APP_DIR__" = ($AppDir -replace '/', '\')
      "__MODULE__" = $Module
    } -Force:$Force

    $AppPath = Join-Path $ProjectRoot $AppDir
    New-Item -ItemType Directory -Path $AppPath -Force | Out-Null
    Write-Template -Template $TemplateScriptsMain -Destination (Join-Path $AppPath "main.py") -Replacements @{
      "__APP_NAME__" = $AppName
    } -Force:$Force
    $InitFile = Join-Path $AppPath "__init__.py"
    if (-not (Test-Path $InitFile)) { Set-Content -Path $InitFile -Value "" -Encoding ASCII }

    Write-Template -Template $TemplateScriptsStart -Destination (Join-Path $ProjectRoot "start.bat") -Replacements @{
      "__MODULE__" = $Module
    } -Force:$Force

    $ReqPath = Join-Path $ProjectRoot $Requirements
    if (-not (Test-Path $ReqPath)) {
      New-Item -ItemType Directory -Path (Split-Path $ReqPath) -Force | Out-Null
      Set-Content -Path $ReqPath -Value "# Add packages here, one per line." -Encoding ASCII
    }

    foreach ($Entry in @("python/", "dist/", "scripts/bin/")) {
      Add-IgnoreEntry $ProjectRoot $Entry
    }

    Write-Host "`n[OK] Portable scripts workspace created in $ProjectRoot" -ForegroundColor Green
    Write-Host "     1. Edit $AppDir\main.py and $Requirements." -ForegroundColor Gray
    Write-Host "     2. Run: .\scripts\build.ps1" -ForegroundColor Gray
    Write-Host "     3. Or double-click start.bat after the first build." -ForegroundColor Gray
    break
  }

  "multi" {
    $AppDirs = @($AppDirs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($AppDirs.Count -eq 0) { throw "-Profile multi requires -AppDirs, e.g. apps/one,apps/two." }
    if ([IO.Path]::IsPathRooted($Workspace)) { throw "-Workspace must be relative for -Profile multi." }

    Add-PortableSubmodule -ProjectRoot $ProjectRoot -SubmodulePath $SubmodulePath `
      -UpstreamUrl $UpstreamUrl -UpstreamRoot $UpstreamRoot -Ref $Ref -Skip:$SkipSubmodule

    $Leaves = @{}
    foreach ($Item in $AppDirs) {
      Assert-RelativePath $Item "-AppDirs"
      $Leaf = Split-Path $Item -Leaf
      if ($Leaves.ContainsKey($Leaf)) { throw "Duplicate app name: $Leaf" }
      $Leaves[$Leaf] = $true

      $AppRequirements = if ([string]::IsNullOrWhiteSpace($Requirements)) { Join-Path $Item "requirements.txt" } else { $Requirements }
      Assert-RelativePath $AppRequirements "-Requirements"
      $AppWorkspace = Join-Path $Item $Workspace

      Write-Template -Template $TemplateApp -Destination (Join-Path $ProjectRoot "scripts\build-$Leaf.ps1") -Replacements @{
        "__APP_DIR__" = ($Item -replace '/', '\')
        "__REQUIREMENTS__" = ($AppRequirements -replace '/', '\')
        "__PYTHON_VERSION__" = $PythonVersion
        "__WORKSPACE__" = ($AppWorkspace -replace '/', '\')
        "__SUBMODULE_PATH__" = ($SubmodulePath -replace '/', '\')
      } -Force:$Force

      if (-not (Test-Path (Join-Path $ProjectRoot $Item))) {
        Write-Host "[WARN] Missing app directory: $Item" -ForegroundColor Yellow
      }
      if (-not (Test-Path (Join-Path $ProjectRoot $AppRequirements))) {
        Write-Host "[WARN] Missing requirements: $AppRequirements" -ForegroundColor Yellow
      }
    }

    $BuildAll = @'
param ([switch]$SkipInstall)

$ErrorActionPreference = "Stop"
$Scripts = Get-ChildItem $PSScriptRoot -Filter "build-*.ps1" |
  Where-Object { $_.Name -ne "build-all.ps1" } |
  Sort-Object Name

foreach ($Script in $Scripts) {
  Write-Host "=== $($Script.BaseName) ===" -ForegroundColor Cyan
  & $Script.FullName -SkipInstall:$SkipInstall
  if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "$($Script.Name) failed (exit $LASTEXITCODE)"
  }
}
'@
    $BuildAllPath = Join-Path $ProjectRoot "scripts\build-all.ps1"
    if ((Test-Path $BuildAllPath) -and -not $Force) {
      throw "$BuildAllPath already exists; use -Force to overwrite."
    }
    Set-Content -Path $BuildAllPath -Value $BuildAll -Encoding UTF8

    Add-IgnoreEntry $ProjectRoot "**/$($Workspace.TrimEnd('/'))/"

    Write-Host "`n[OK] Multi-app scripts created under $(Join-Path $ProjectRoot 'scripts')" -ForegroundColor Green
    Write-Host "     Build one: .\scripts\build-<app>.ps1" -ForegroundColor Gray
    Write-Host "     Build all: .\scripts\build-all.ps1" -ForegroundColor Gray
    break
  }
}
