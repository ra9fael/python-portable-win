# Shared download-integrity helpers. Dot-source this file, then pass the data
# table loaded from checksums.psd1.

function Get-PinnedSha256
{
  param(
    [string]$Key,
    [string]$Override,
    [hashtable]$Table
  )

  if (-Not [string]::IsNullOrWhiteSpace($Override))
  {
    return $Override.Trim().ToLowerInvariant()
  }
  if ($null -ne $Table -and $Table.ContainsKey($Key))
  {
    return ([string]$Table[$Key]).Trim().ToLowerInvariant()
  }
  return $null
}

function Assert-Sha256
{
  param(
    [string]$Path,
    [string]$Expected,
    [string]$Label,
    [switch]$Skip
  )

  if (-Not (Test-Path $Path))
  {
    throw "Cannot verify a missing file: $Path"
  }
  if ($Skip)
  {
    Write-Host "[WARN] Checksum skipped for $Label (-SkipChecksum)." -ForegroundColor Yellow
    return
  }
  if ([string]::IsNullOrWhiteSpace($Expected))
  {
    Write-Host "[WARN] No SHA256 pinned for $Label; skipping verification." -ForegroundColor Yellow
    return
  }

  $Actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($Actual -ne $Expected)
  {
    throw "SHA256 mismatch for $Label`n  expected: $Expected`n  actual:   $Actual"
  }
  Write-Host "[OK] SHA256 verified: $Label" -ForegroundColor Green
}
