#requires -Version 7.6

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "Windows Task Scheduler installation is only supported on Windows."
}

$taskName = "nix-dotfiles-tool-update"
$script = Join-Path -Path $HOME -ChildPath ".local\bin\nix-dotfiles-tool-update.ps1"

if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Updater script not found: $script"
}

$pwsh = Get-Command -Name "pwsh.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $pwsh) {
    throw "PowerShell 7.6+ (pwsh.exe) is required to install the scheduled updater."
}

$arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$script`""

if (Get-Command -Name "Register-ScheduledTask" -ErrorAction SilentlyContinue) {
    $action = New-ScheduledTaskAction -Execute $pwsh.Source -Argument $arguments
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(5) `
        -RepetitionInterval (New-TimeSpan -Hours 6) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Run nix-dotfiles tool updater every six hours." `
        -Force | Out-Host
} else {
    $taskRun = "`"$($pwsh.Source)`" $arguments"

    & schtasks.exe /Create /TN $taskName /SC HOURLY /MO 6 /TR $taskRun /F | Out-Host
}
