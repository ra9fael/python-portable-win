# Shared helpers for consumer-mode builds.
# A workspace is the directory that owns python/, scripts/, requirements and dist/.
# Defaults to the parent of scripts/; -Workspace points it at an app's .portable/.

function Resolve-PortableWorkspace {
    param(
        [string]$Workspace,
        [string]$ScriptDir
    )

    if ([string]::IsNullOrWhiteSpace($Workspace)) {
        return (Resolve-Path (Join-Path $ScriptDir "..")).Path
    }
    if (-not (Test-Path -LiteralPath $Workspace)) {
        throw "Workspace not found: $Workspace (create it before building, e.g. .portable\)."
    }
    return (Resolve-Path -LiteralPath $Workspace).Path
}

function Initialize-PortableRuntime {
    param(
        [string]$WorkspaceDir,
        [string]$ScriptDir
    )

    $runtime = Join-Path $WorkspaceDir "scripts"
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null

    foreach ($name in @("repair.py", "sitecustomize.py"))
    {
        $source = Join-Path $ScriptDir $name
        $target = Join-Path $runtime $name
        $existing = Resolve-Path -LiteralPath $target -ErrorAction SilentlyContinue
        if (-not $existing -or $existing.Path -ne (Resolve-Path -LiteralPath $source).Path)
        {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
    return $runtime
}
