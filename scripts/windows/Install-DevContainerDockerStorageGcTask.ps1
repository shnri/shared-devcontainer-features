[CmdletBinding()]
param(
    [string]$TaskName = 'DevContainerSafeDockerGc',
    [datetime]$At = (Get-Date '03:00'),
    [string]$StorageScriptPath = (Join-Path $PSScriptRoot 'DevContainerDockerStorage.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $StorageScriptPath -PathType Leaf)) {
    throw "Docker storage script was not found: $StorageScriptPath"
}

$powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$StorageScriptPath`" -Mode Gc"
$action = New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Daily -At $At
# InteractiveToken keeps the task in the user's Docker Desktop context; it does not require a password.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Installed daily safe Docker GC task '$TaskName' for $($principal.UserId) at $($At.ToString('HH:mm'))."
Write-Output 'The task only prunes BuildKit cache, gc=ephemeral resources, and unused devcontainer.metadata images older than 168h.'
