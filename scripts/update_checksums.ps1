param (
  # Defaults to python/.portable_version, then 3.14.7.
  [string]$Version = "",
  [string[]]$Arch = @("amd64"),
  [string]$Mirror = "",
  [switch]$SkipTclTk,
  # Consumer mode: read python/.portable_version from this workspace.
  [string]$Workspace = "",
  # Optional output table; defaults to scripts/checksums.psd1.
  [string]$ChecksumFile = ""
)

$ErrorActionPreference = "Stop"

# Downloads the requested artifacts and rewrites checksums.psd1.
# Existing entries for other versions/architectures are preserved.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "workspace.ps1")
$WorkspaceDir = Resolve-PortableWorkspace -Workspace $Workspace -ScriptDir $ScriptDir
if ([string]::IsNullOrWhiteSpace($ChecksumFile))
{
  $ChecksumFile = Join-Path $ScriptDir "checksums.psd1"
}
else
{
  $ChecksumFile = [IO.Path]::GetFullPath($ChecksumFile)
}
$VersionFile = Join-Path $WorkspaceDir "python\.portable_version"

if ([string]::IsNullOrWhiteSpace($Version))
{
  if (Test-Path $VersionFile)
  {
    $Version = (Get-Content $VersionFile -Raw).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($Version))
  {
    $Version = "3.14.7"
  }
}

$BaseUrl = if ([string]::IsNullOrWhiteSpace($Mirror))
{
  "https://www.python.org/ftp/python"
}
else
{
  $Mirror.TrimEnd('/')
}

$TempDir = Join-Path $env:TEMP "portable-checksums-$PID"
if (Test-Path $TempDir)
{ Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

$Hashes = @{}
if (Test-Path $ChecksumFile)
{
  $Hashes = Import-PowerShellDataFile $ChecksumFile
}

function Get-ArtifactHash
{
  param([string]$Url, [string]$Name)

  $Path = Join-Path $TempDir $Name
  Invoke-WebRequest -Uri $Url -OutFile $Path
  $Hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "[OK] $Name  $Hash" -ForegroundColor Green
  return $Hash
}

try
{
  foreach ($TargetArch in $Arch)
  {
    $ZipName = "python-$Version-embed-$TargetArch.zip"
    $ZipUrl = "$BaseUrl/$Version/$ZipName"
    $Hashes[$ZipName] = Get-ArtifactHash -Url $ZipUrl -Name $ZipName

    if (-Not $SkipTclTk)
    {
      $MsiName = "tcltk-$Version-$TargetArch.msi"
      $MsiUrl = "$BaseUrl/$Version/$TargetArch/tcltk.msi"
      try
      {
        $Hashes[$MsiName] = Get-ArtifactHash -Url $MsiUrl -Name $MsiName
      }
      catch
      {
        Write-Host "[WARN] No tcltk.msi for $Version/$TargetArch; keeping the existing entry." -ForegroundColor Yellow
      }
    }
  }

  # get-pip.py is a rolling upstream file; refresh it on every run.
  $Hashes["get-pip.py"] = Get-ArtifactHash -Url "https://bootstrap.pypa.io/get-pip.py" -Name "get-pip.py"
}
catch
{
  Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "        checksums.psd1 was not modified." -ForegroundColor Red
  Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
  Exit 1
}

$Lines = @(
  "# SHA256 checksums for downloaded bootstrap artifacts.",
  "# Refresh with: .\scripts\update_checksums.ps1 -Version <x.y.z> -Arch amd64,arm64,win32",
  "# get-pip.py is a rolling upstream file: refresh its hash when PyPA ships a new pip.",
  "",
  "@{"
)
foreach ($Key in ($Hashes.Keys | Sort-Object))
{
  $Lines += "    '$Key' = '$($Hashes[$Key])'"
}
$Lines += "}"

Set-Content -Path $ChecksumFile -Value $Lines -Encoding ASCII
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n[OK] Updated $ChecksumFile" -ForegroundColor Green
$Hashes.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
