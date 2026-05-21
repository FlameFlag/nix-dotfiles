#Requires -Version 5.1
# Windows still ships with old Windows PowerShell, so this wrapper exists only
# to bootstrap a modern PowerShell and hand off to bootstrap-pwsh.ps1.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SkipPowerShellUpdate', Justification = 'Script parameter is consumed by nested bootstrap helper functions.')]
[CmdletBinding()]
param(
    [switch] $SkipPowerShellUpdate,
    [switch] $SkipZigCheck,
    [switch] $SkipMsvcBuildTools
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $false)]
        [string[]] $ArgumentList = @()
    )

    Write-Output "> $FilePath $($ArgumentList -join ' ')"
    & $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Output $_ }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Invoke-WebFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Uri,

        [Parameter(Mandatory = $true)]
        [string] $OutFile
    )

    if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
        return
    }

    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Uri, $OutFile)
    } finally {
        $client.Dispose()
    }
}

function Test-PwshCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    if ($Path -like '*\Microsoft\WindowsApps\*') {
        return $false
    }

    try {
        $major = & $Path -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major' 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        $parsed = 0
        return [int]::TryParse([string] ($major | Select-Object -First 1), [ref] $parsed) -and $parsed -ge 7
    } catch {
        return $false
    }
}

function Find-Pwsh {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\powershell\pwsh.exe')
    )

    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }

    foreach ($candidate in $candidates) {
        if (Test-PwshCandidate -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }

    & $winget.Source @ArgumentList 2>&1 | ForEach-Object { Write-Output $_ }
    $exitCode = $LASTEXITCODE
    return ($exitCode -eq 0)
}

function Install-OrUpdate-Pwsh {
    if (-not $SkipPowerShellUpdate) {
        [void] (Invoke-Winget -ArgumentList @(
            'upgrade',
            '--id', 'Microsoft.PowerShell',
            '--source', 'winget',
            '--silent',
            '--accept-source-agreements',
            '--accept-package-agreements',
            '--disable-interactivity'
        ))
    }

    if (Find-Pwsh) {
        return
    }

    [void] (Invoke-Winget -ArgumentList @(
        'install',
        '--id', 'Microsoft.PowerShell',
        '--source', 'winget',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    ))

    if (Find-Pwsh) {
        return
    }

    $destination = Join-Path $env:LOCALAPPDATA 'Microsoft\powershell'
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) ("install-powershell-{0}.ps1" -f [System.Guid]::NewGuid())
    try {
        Invoke-WebFile -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $installer
        Invoke-Native -FilePath powershell.exe -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $installer,
            '-Destination', $destination,
            '-AddToPath'
        )
    } finally {
        if (Test-Path -LiteralPath $installer) {
            Remove-Item -LiteralPath $installer -Force
        }
    }
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Install-OrUpdate-Pwsh

$pwsh = Find-Pwsh
if (-not $pwsh) {
    throw 'Unable to find pwsh after installing PowerShell.'
}

$scriptDir = Split-Path -Parent $PSCommandPath
$modernBootstrap = Join-Path $scriptDir 'bootstrap-pwsh.ps1'
$forward = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $modernBootstrap
)
if ($SkipZigCheck) {
    $forward += '-SkipZigCheck'
}
if ($SkipMsvcBuildTools) {
    $forward += '-SkipMsvcBuildTools'
}

Invoke-Native -FilePath $pwsh -ArgumentList $forward
