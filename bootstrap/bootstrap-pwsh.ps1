#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SkipMsvcBuildTools', Justification = 'Script parameter is consumed by nested bootstrap helper functions.')]
[CmdletBinding()]
param(
    [switch] $SkipZigCheck,
    [switch] $SkipMsvcBuildTools
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# PowerShell 7 can turn native non-zero exits into terminating errors before we
# get a chance to print the command output. This wrapper temporarily opts out so
# bootstrap failures show the real tool output and then fail with one clear
# exception.
function Invoke-Native {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $ArgumentList = @()
    )

    Write-Output "> $FilePath $($ArgumentList -join ' ')"
    $oldErrorActionPreference = $ErrorActionPreference
    $hasNativeErrorPreference = Test-Path -LiteralPath 'Variable:\PSNativeCommandUseErrorActionPreference'
    if ($hasNativeErrorPreference) {
        $oldNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    }

    $ErrorActionPreference = 'Continue'
    if ($hasNativeErrorPreference) {
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object { Write-Output $_ }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $oldNativeErrorPreference
        }
    }

    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
}

# Same native-command guard as Invoke-Native, but for short status probes where
# we want a single display line instead of a hard failure. This keeps the final
# summary useful even if an optional tool is not installed yet.
function Get-NativeText {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $ArgumentList = @()
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $hasNativeErrorPreference = Test-Path -LiteralPath 'Variable:\PSNativeCommandUseErrorActionPreference'
    if ($hasNativeErrorPreference) {
        $oldNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    }

    $ErrorActionPreference = 'Continue'
    if ($hasNativeErrorPreference) {
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $output = & $FilePath @ArgumentList 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "error:${LASTEXITCODE}"
        }

        return (($output | Out-String).Trim() -split '\r?\n')[0]
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($hasNativeErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $oldNativeErrorPreference
        }
    }
}

# Invoke-WebRequest progress rendering is surprisingly expensive on Windows
# consoles. Suppressing it makes large Zig downloads much faster and keeps the
# bootstrap log readable.
function Invoke-WebFile {
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $OutFile
    )

    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    } finally {
        $ProgressPreference = $oldProgressPreference
    }
}

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir '..')).Path
}

function Get-LocalRoot {
    # Git Bash, PowerShell, and elevated shells do not always agree on HOME.
    # The rest of this repo expects the Unix-like ~/.local layout, so normalize
    # HOME from USERPROFILE when PowerShell did not receive it.
    if ([string]::IsNullOrWhiteSpace($env:HOME)) {
        $env:HOME = $env:USERPROFILE
    }
    return $env:HOME
}

function Add-PathEntry {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    # Prepend only once. The freshly managed tools should win for this process,
    # but we do not want PATH to grow every time a helper calls Add-PathEntry.
    $entries = $env:PATH -split [System.IO.Path]::PathSeparator
    if ($entries -notcontains $Path) {
        $env:PATH = "$Path$([System.IO.Path]::PathSeparator)$env:PATH"
    }
}

function Get-CargoBin {
    if (-not [string]::IsNullOrWhiteSpace($env:CARGO_HOME)) {
        return (Join-Path $env:CARGO_HOME 'bin')
    }

    return (Join-Path (Get-LocalRoot) '.cargo\bin')
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    # WinGet is optional because some Server/Core or corporate images do not
    # include it. Callers use the boolean return plus LastWingetExitCode to
    # decide whether to continue with a fallback.
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }

    & $winget.Source @ArgumentList 2>&1 | ForEach-Object { Write-Output $_ }
    $script:LastWingetExitCode = $LASTEXITCODE
    return ($script:LastWingetExitCode -eq 0)
}

function Test-MsvcBuildToolset {
    # Rust's default Windows target needs the MSVC linker and Windows SDK.
    # vswhere is the supported Visual Studio discovery API, so use it instead of
    # guessing install directories by hand.
    $vswhereCandidates = @()
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $vswhereCandidates += (Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $vswhereCandidates += (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    }

    foreach ($candidate in $vswhereCandidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        $installPath = & $candidate -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($installPath)) {
            return $true
        }
    }

    return $false
}

function Install-MsvcBuildToolset {
    if ($SkipMsvcBuildTools -or (Test-MsvcBuildToolset)) {
        return (Test-MsvcBuildToolset)
    }

    # Install only the native build pieces we need. The override keeps the
    # Visual Studio installer passive and avoids pulling in full IDE workloads.
    $installed = Invoke-Winget -ArgumentList @(
        'install',
        '--id', 'Microsoft.VisualStudio.2022.BuildTools',
        '--source', 'winget',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity',
        '--override', '--wait --passive --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --addProductLang En-us'
    )

    if (-not $installed -or -not (Test-MsvcBuildToolset)) {
        $exitCode = if ($null -ne $script:LastWingetExitCode) { $script:LastWingetExitCode } else { 'unknown' }
        Write-Warning "Native Windows Rust builds need MSVC C++ build tools and a Windows SDK, but WinGet did not finish installing them (exit: ${exitCode})."
        return $false
    }

    return $true
}

function Read-ZigArtifact {
    param(
        [Parameter(Mandatory)]
        [string] $ArtifactsFile,

        [string] $Version
    )

    # Match the POSIX bootstrap script: Zig downloads are pinned in a tiny TSV
    # file so the script does not need JSON parsing before Zig is available.
    foreach ($line in Get-Content -LiteralPath $ArtifactsFile) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = $trimmed -split '\s+'
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Version = $parts[0]
        }

        if ($parts.Count -ge 4 -and $parts[0] -eq $Version -and $parts[1] -eq 'x86_64-windows') {
            return @{
                Version = $parts[0]
                Url = $parts[2]
                Sha256 = $parts[3]
            }
        }
    }

    throw "Unsupported pinned Zig bootstrap artifact: ${Version} x86_64-windows"
}

function Install-Zig {
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $LocalBin,

        [Parameter(Mandatory)]
        [string] $LocalOpt
    )

    # Everything after this point is built by Zig, so first ensure that the
    # manifest-selected Zig version is available and shimmed into ~/.local/bin.
    $artifact = Read-ZigArtifact -ArtifactsFile (Join-Path $RepoRoot 'bootstrap\zig-artifacts.tsv') -Version $env:BOOTSTRAP_ZIG_VERSION
    $version = $artifact.Version
    $zigParent = Join-Path $LocalOpt 'zig'
    $zigDir = Join-Path $zigParent $version
    $zigExe = Join-Path $zigDir 'zig.exe'
    $zigShim = Join-Path $LocalBin 'zig.cmd'

    # Older bootstraps may have copied zig.exe directly into ~/.local/bin.
    # Prefer a shim so all Zig files live together under ~/.local/opt/zig/$version.
    $localZigExe = Join-Path $LocalBin 'zig.exe'
    if (Test-Path -LiteralPath $localZigExe) { Remove-Item -LiteralPath $localZigExe -Force }

    # Fast path: the pinned Zig is already installed where this script manages
    # it. Recreate the shim in case the user deleted ~/.local/bin/zig.cmd.
    if (Test-Path -LiteralPath $zigExe) {
        $actual = (& $zigExe version).Trim()
        if ($actual -eq $version) {
            @(
                '@echo off',
                '"' + $zigExe + '" %*'
            ) | Set-Content -LiteralPath $zigShim -Encoding ascii
            return $zigExe
        }
    }

    # If the user already has the exact pinned Zig on PATH, use it instead of
    # downloading another copy. Requiring the adjacent lib directory avoids
    # accepting a partial binary-only install that cannot run `zig build`.
    $current = Get-Command zig -ErrorAction SilentlyContinue
    if ($current) {
        try {
            $actual = (& $current.Source version).Trim()
            $installRoot = Split-Path -Parent $current.Source
            if ($actual -eq $version -and (Test-Path -LiteralPath (Join-Path $installRoot 'lib'))) {
                @(
                    '@echo off',
                    '"' + $current.Source + '" %*'
                ) | Set-Content -LiteralPath $zigShim -Encoding ascii
                return $current.Source
            }
        } catch {
            Write-Verbose "Ignoring unusable zig on PATH: $($current.Source)"
        }
    }

    # Slow path: download the pinned archive, verify its hash, extract into a
    # temporary directory, and only then move it into the stable install path.
    $downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zig-bootstrap-{0}" -f [System.Guid]::NewGuid())
    $archive = Join-Path $downloadDir 'zig.zip'
    $extractDir = Join-Path $downloadDir 'extract'

    New-Item -ItemType Directory -Force -Path $zigParent, $downloadDir, $extractDir | Out-Null
    try {
        Invoke-WebFile -Uri $artifact.Url -OutFile $archive
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
        if ($actualHash -ne $artifact.Sha256) {
            throw "Checksum mismatch for ${archive}: expected $($artifact.Sha256), actual ${actualHash}"
        }

        Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
        $extractedRoot = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
        if (-not $extractedRoot) {
            throw 'Zig archive did not contain a root directory.'
        }

        if (Test-Path -LiteralPath $zigDir) {
            Remove-Item -LiteralPath $zigDir -Recurse -Force
        }
        Move-Item -LiteralPath $extractedRoot.FullName -Destination $zigDir

        if ((& $zigExe version).Trim() -ne $version) {
            throw "Downloaded Zig did not report expected version ${version}."
        }

        @(
            '@echo off',
            '"' + $zigExe + '" %*'
        ) | Set-Content -LiteralPath $zigShim -Encoding ascii
        return $zigExe
    } finally {
        if (Test-Path -LiteralPath $downloadDir) {
            Remove-Item -LiteralPath $downloadDir -Recurse -Force
        }
    }
}

function Invoke-ZigBootstrapInstaller {
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $ZigExe
    )

    # Pass repo-local paths through the environment so the Zig code can stay
    # relocatable and testable. Restore the caller's environment afterwards
    # because users often run this from an interactive PowerShell session.
    $oldToolsJson = $env:BOOTSTRAP_TOOLS_JSON
    $oldRepoDir = $env:BOOTSTRAP_REPO_DIR
    $oldZigExe = $env:BOOTSTRAP_ZIG_EXE
    try {
        $env:BOOTSTRAP_TOOLS_JSON = Join-Path $RepoRoot 'bootstrap\dev_tools\tools\tools.json'
        $env:BOOTSTRAP_REPO_DIR = $RepoRoot
        $env:BOOTSTRAP_ZIG_EXE = $ZigExe
        Invoke-Native -FilePath $ZigExe -ArgumentList @(
            'run',
            '--dep', 'bootstrap',
            '--dep', 'common',
            "-Mroot=$(Join-Path $RepoRoot 'bootstrap\dev_tools\main.zig')",
            '--dep', 'common',
            "-Mbootstrap=$(Join-Path $RepoRoot 'lib\zig\bootstrap\root.zig')",
            "-Mcommon=$(Join-Path $RepoRoot 'lib\zig\common\root.zig')",
            '--',
            'install'
        )
    } finally {
        $env:BOOTSTRAP_TOOLS_JSON = $oldToolsJson
        $env:BOOTSTRAP_REPO_DIR = $oldRepoDir
        $env:BOOTSTRAP_ZIG_EXE = $oldZigExe
    }
}

function Add-OrSet-NoteProperty {
    param(
        [Parameter(Mandatory)]
        [psobject] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    # Windows Terminal settings are user-edited JSON. Mutate only the properties
    # we own and preserve any unknown fields instead of recreating the file from
    # a rigid schema.
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        $InputObject.$Name = $Value
        return
    }

    $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
}

function Get-WindowsTerminalSettingsPath {
    # Terminal has used several package identities/locations over time. Check
    # each known path and silently skip the ones this machine does not have.
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $paths += (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        $paths += (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
        $paths += (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    }

    return $paths
}

function Get-CurrentPwshPath {
    # Prefer the PowerShell running this script; it is known-good and avoids
    # accidentally pointing Terminal at Windows PowerShell 5.1.
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    if (Test-Path -LiteralPath $pwsh) {
        return $pwsh
    }

    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Set-WindowsTerminalDefaultPowerShell {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $pwsh = Get-CurrentPwshPath
    if (-not $pwsh) {
        return
    }

    # Use PowerShell's well-known Terminal profile GUID. Existing generated
    # profiles usually use this GUID or the Windows.Terminal.PowershellCore
    # source marker, so we update those instead of creating duplicates.
    $pwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $pwshProfile = [ordered]@{
        guid = $pwshGuid
        name = 'PowerShell'
        commandline = $pwsh
        hidden = $false
    }

    foreach ($settingsPath in Get-WindowsTerminalSettingsPath) {
        $settingsDir = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $settingsDir)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $settingsPath)) {
            continue
        }

        $rawSettings = Get-Content -LiteralPath $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($rawSettings)) {
            $settings = [pscustomobject]@{}
        } else {
            try {
                $settings = $rawSettings | ConvertFrom-Json
            } catch {
                Write-Warning "Skipping Windows Terminal settings with invalid JSON: ${settingsPath}"
                continue
            }
        }

        if (-not ($settings.PSObject.Properties.Name -contains 'profiles') -or $null -eq $settings.profiles) {
            Add-OrSet-NoteProperty -InputObject $settings -Name 'profiles' -Value ([pscustomobject]@{})
        }

        if (-not ($settings.profiles.PSObject.Properties.Name -contains 'list') -or $null -eq $settings.profiles.list) {
            Add-OrSet-NoteProperty -InputObject $settings.profiles -Name 'list' -Value @()
        }

        $profiles = @($settings.profiles.list)
        $existing = $profiles | Where-Object {
            ($_.PSObject.Properties.Name -contains 'guid' -and $_.guid -eq $pwshGuid) -or
            ($_.PSObject.Properties.Name -contains 'source' -and $_.source -eq 'Windows.Terminal.PowershellCore')
        } | Select-Object -First 1

        if ($existing) {
            Add-OrSet-NoteProperty -InputObject $existing -Name 'guid' -Value $pwshGuid
            Add-OrSet-NoteProperty -InputObject $existing -Name 'hidden' -Value $false
            if ($existing.PSObject.Properties.Name -contains 'source') {
                if ($existing.PSObject.Properties.Name -contains 'commandline') {
                    $existing.PSObject.Properties.Remove('commandline')
                }
            } else {
                Add-OrSet-NoteProperty -InputObject $existing -Name 'commandline' -Value $pwsh
            }
        } else {
            $profiles += [pscustomobject]$pwshProfile
        }

        Add-OrSet-NoteProperty -InputObject $settings.profiles -Name 'list' -Value $profiles
        Add-OrSet-NoteProperty -InputObject $settings -Name 'defaultProfile' -Value $pwshGuid

        if ($PSCmdlet.ShouldProcess($settingsPath, 'Set Windows Terminal default profile to PowerShell 7')) {
            try {
                $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $settingsPath -Encoding utf8
                Write-Output "Windows Terminal default profile: PowerShell 7 (${settingsPath})"
            } catch {
                Write-Warning "Skipping Windows Terminal settings that could not be updated: ${settingsPath}: $($_.Exception.Message)"
            }
        }
    }
}

$repoRoot = Get-RepoRoot
$homeRoot = Get-LocalRoot
$localBin = Join-Path $homeRoot '.local\bin'
$localOpt = Join-Path $homeRoot '.local\opt'
$cargoBin = Get-CargoBin
New-Item -ItemType Directory -Force -Path $localBin, $localOpt | Out-Null
Add-PathEntry -Path $localBin

$zig = Install-Zig -RepoRoot $repoRoot -LocalBin $localBin -LocalOpt $localOpt
$hasMsvcBuildTools = Install-MsvcBuildToolset
if (-not $hasMsvcBuildTools) {
    throw 'Rust on Windows requires MSVC C++ build tools and a Windows SDK. Re-run without -SkipMsvcBuildTools or install Visual Studio Build Tools manually.'
}
$env:BOOTSTRAP_RUST_TOOLCHAIN = 'stable'
Invoke-ZigBootstrapInstaller -RepoRoot $repoRoot -ZigExe $zig
Add-PathEntry -Path $cargoBin
try {
    Set-WindowsTerminalDefaultPowerShell
} catch {
    Write-Warning "Skipping Windows Terminal default profile update: $($_.Exception.Message)"
}

if (-not $SkipZigCheck) {
    Push-Location $repoRoot
    try {
        Invoke-Native -FilePath $zig -ArgumentList @('build', 'check')
    } finally {
        Pop-Location
    }
}

Write-Output "PowerShell: $($PSVersionTable.PSVersion)"
Write-Output "zig: $(Get-NativeText -FilePath $zig -ArgumentList @('version'))"
$chezmoi = Get-Command chezmoi.exe -ErrorAction SilentlyContinue
if ($chezmoi) {
    Write-Output "chezmoi: $(Get-NativeText -FilePath $chezmoi.Source -ArgumentList @('--version'))"
}
$rustup = Get-Command rustup.exe -ErrorAction SilentlyContinue
if ($rustup) {
    Write-Output "rustup: $(Get-NativeText -FilePath $rustup.Source -ArgumentList @('--version'))"
}
