[CmdletBinding()]
param(
    [ValidateSet('Status', 'Gc')]
    [string]$Mode = 'Status',
    [string]$MaxCacheSize = '10GB',
    [string]$UnusedFor = '168h'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Docker {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Show-DaemonBoundary {
    $dockerHost = if ($env:DOCKER_HOST) { $env:DOCKER_HOST } else { 'Docker Desktop default local context' }
    $dockerContext = if ($env:DOCKER_CONTEXT) { $env:DOCKER_CONTEXT } else { (& docker context show 2>$null) }
    if ([string]::IsNullOrWhiteSpace($dockerContext)) { $dockerContext = 'default' }

    Write-Output 'Docker daemon boundary (Windows host Docker Desktop)'
    Write-Output "  DOCKER_HOST: $dockerHost"
    Write-Output "  Docker context: $dockerContext"
    Invoke-Docker info '--format' '  Server: {{.ServerVersion}}; Docker root: {{.DockerRootDir}}; Daemon labels: {{json .Labels}}'
}

Invoke-Docker info | Out-Null
Show-DaemonBoundary

if ($Mode -eq 'Status') {
    Write-Output "`nDocker system usage (Windows host daemon)"
    Invoke-Docker system df
    Write-Output "`nBuildKit usage (Windows host daemon)"
    try {
        Invoke-Docker buildx du
    }
    catch {
        Write-Warning 'Buildx usage is unavailable for the selected daemon.'
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($MaxCacheSize) -or [string]::IsNullOrWhiteSpace($UnusedFor)) {
    throw 'MaxCacheSize and UnusedFor must not be empty.'
}

Write-Output "`nSafe Docker GC (Windows host daemon)"
Write-Output "  BuildKit cache maximum: $MaxCacheSize"
Write-Output "  Dev Container image age threshold: $UnusedFor"

# BuildKit cache is bounded separately from images and volumes.
$builderPruneHelp = (Invoke-Docker builder prune '--help') -join "`n"
if ($builderPruneHelp -match '--max-used-space') {
    Invoke-Docker builder prune '--all' '--force' '--max-used-space' $MaxCacheSize
}
else {
    # Docker 28以前との互換用。Docker 29以降では--keep-storageは予約容量なので使わない。
    Invoke-Docker builder prune '--all' '--force' '--keep-storage' $MaxCacheSize
}
# Only Compose/E2E resources explicitly labelled gc=ephemeral are eligible.
Invoke-Docker container prune '--force' '--filter' 'label=gc=ephemeral'
Invoke-Docker image prune '--all' '--force' '--filter' 'label=gc=ephemeral'
# -a includes unused named volumes, but the label filter protects development databases.
Invoke-Docker volume prune '--all' '--force' '--filter' 'label=gc=ephemeral'
# Docker image prune never removes images referenced by containers; devcontainer metadata narrows candidates.
Invoke-Docker image prune '--all' '--force' '--filter' 'label=devcontainer.metadata' '--filter' "until=$UnusedFor"
