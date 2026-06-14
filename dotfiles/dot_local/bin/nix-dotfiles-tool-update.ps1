#requires -Version 7.6

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Write-UpdaterLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message
    )

    $stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    [Console]::Out.WriteLine("$stamp $Message")
}

function Add-PathPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Paths
    )

    $existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in ($env:Path -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) {
            [void] $existing.Add($entry)
        }
    }

    foreach ($path in $Paths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and
            (Test-Path -LiteralPath $path) -and
            -not $existing.Contains($path)) {
            $env:Path = $path + [System.IO.Path]::PathSeparator + $env:Path
            [void] $existing.Add($path)
        }
    }
}

function Get-ApplicationCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.CommandInfo] $Command,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    & $Command.Source @Arguments | ForEach-Object {
        [Console]::Out.WriteLine($_)
    }
    if ($null -eq $LASTEXITCODE) {
        return 0
    }

    return $LASTEXITCODE
}

function Invoke-ManifestUpdater {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet("bun-global", "uv-tool", "uv-tool-source")]
        [string] $Provider,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Target,

        [string] $Source = ""
    )

    Write-UpdaterLog "running manifest updater: $Name ($Provider)"

    switch ($Provider) {
        "bun-global" {
            $runner = Get-ApplicationCommand -Name "bun"
            if ($null -eq $runner) {
                Write-UpdaterLog "skipping ${Name}: bun not found"
                return 127
            }

            return Invoke-NativeCommand -Command $runner -Arguments @("install", "--global", $Target)
        }
        "uv-tool" {
            $runner = Get-ApplicationCommand -Name "uv"
            if ($null -eq $runner) {
                Write-UpdaterLog "skipping ${Name}: uv not found"
                return 127
            }

            return Invoke-NativeCommand -Command $runner -Arguments @("tool", "upgrade", $Target)
        }
        "uv-tool-source" {
            $runner = Get-ApplicationCommand -Name "uv"
            if ($null -eq $runner) {
                Write-UpdaterLog "skipping ${Name}: uv not found"
                return 127
            }
            if ([string]::IsNullOrWhiteSpace($Source)) {
                Write-UpdaterLog "skipping ${Name}: uv-tool-source requires a source"
                return 2
            }

            return Invoke-NativeCommand -Command $runner -Arguments @("tool", "install", "--force", "--reinstall", "--refresh", "$Target @ $Source")
        }
    }
}

function Remove-TomlComment {
    [CmdletBinding()]
    param(
        [string] $Line
    )

    $out = [System.Text.StringBuilder]::new()
    $quote = [char] 0
    for ($i = 0; $i -lt $Line.Length; $i += 1) {
        $ch = $Line[$i]
        if ($quote -ne [char] 0) {
            [void] $out.Append($ch)
            if ($ch -eq $quote) {
                $quote = [char] 0
            } elseif ($quote -eq '"' -and $ch -eq '\' -and ($i + 1) -lt $Line.Length) {
                $i += 1
                [void] $out.Append($Line[$i])
            }
            continue
        }

        if ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            [void] $out.Append($ch)
        } elseif ($ch -eq "#") {
            break
        } else {
            [void] $out.Append($ch)
        }
    }

    return $out.ToString().Trim()
}

function ConvertFrom-UpdaterTomlValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $value = $Value.Trim()
    if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
        $value = $value.Replace('\"', '"').Replace('\\', '\')
    } elseif ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value
}

function ConvertFrom-SimpleToolUpdateToml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $Path
    )

    $tools = [System.Collections.Generic.List[hashtable]]::new()
    $currentTool = $null
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = Remove-TomlComment -Line $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -eq "[[tools]]" -or $line -eq "[[tool]]") {
            if ($null -ne $currentTool) {
                $tools.Add($currentTool)
            }
            $currentTool = @{}
            continue
        }

        if ($line.StartsWith("[")) {
            throw "Unsupported manifest table: $line"
        }

        if ($null -eq $currentTool -or -not $line.Contains("=")) {
            throw "Invalid manifest line: $line"
        }

        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim().ToLowerInvariant()
        $value = ConvertFrom-UpdaterTomlValue -Value $parts[1]
        switch ($key) {
            "name" { $currentTool.name = $value }
            "provider" { $currentTool.provider = $value }
            "package" { $currentTool.package = $value }
            "target" { $currentTool.target = $value }
            "source" { $currentTool.source = $value }
            "enabled" { $currentTool.enabled = $value }
            default { Write-UpdaterLog "ignoring unknown manifest key: $key" }
        }
    }

    if ($null -ne $currentTool) {
        $tools.Add($currentTool)
    }

    return $tools
}

function ConvertFrom-PythonToolUpdateToml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $Path
    )

    $pythonScript = @'
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as manifest:
    data = tomllib.load(manifest)

tools = data.get("tools", data.get("tool", []))
if isinstance(tools, dict):
    tools = [tools]

if not isinstance(tools, list):
    raise TypeError("manifest key 'tools' must be an array of tables")

print(json.dumps(tools, separators=(",", ":")))
'@

    $candidates = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($name in @("python3", "python")) {
        $command = Get-ApplicationCommand -Name $name
        if ($null -ne $command) {
            $candidates.Add(@{ Command = $command; Arguments = @("-c", $pythonScript, $Path) })
        }
    }

    $py = Get-ApplicationCommand -Name "py"
    if ($null -ne $py) {
        $candidates.Add(@{ Command = $py; Arguments = @("-3", "-c", $pythonScript, $Path) })
    }

    foreach ($candidate in $candidates) {
        try {
            $output = & $candidate.Command.Source @($candidate.Arguments) 2>$null
            $json = ($output | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $json.StartsWith("[")) {
                return @($json | ConvertFrom-Json -AsHashtable)
            }
        } catch {
            continue
        }
    }

    return $null
}

function ConvertFrom-ToolUpdateToml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string] $Path
    )

    $tools = ConvertFrom-PythonToolUpdateToml -Path $Path
    if ($null -ne $tools) {
        return $tools
    }

    Write-UpdaterLog "python tomllib unavailable; using limited built-in TOML reader"
    return ConvertFrom-SimpleToolUpdateToml -Path $Path
}

function Get-ManifestValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Tool,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Names
    )

    foreach ($name in $Names) {
        if ($Tool.ContainsKey($name)) {
            return [string] $Tool[$name]
        }
    }

    return ""
}

function Invoke-ManifestTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Tool
    )

    $enabled = Get-ManifestValue -Tool $Tool -Names @("enabled")
    if ([string]::IsNullOrWhiteSpace($enabled)) {
        $enabled = "true"
    }

    $name = Get-ManifestValue -Tool $Tool -Names @("name")
    if ($enabled -eq "false") {
        Write-UpdaterLog "skipping disabled manifest updater: $name"
        return 0
    }

    $provider = Get-ManifestValue -Tool $Tool -Names @("provider")
    $target = Get-ManifestValue -Tool $Tool -Names @("package", "target")
    $source = Get-ManifestValue -Tool $Tool -Names @("source")

    if ([string]::IsNullOrWhiteSpace($name) -or
        [string]::IsNullOrWhiteSpace($provider) -or
        [string]::IsNullOrWhiteSpace($target)) {
        Write-UpdaterLog "invalid manifest tool entry: name, provider, and package are required"
        return 2
    }

    try {
        return Invoke-ManifestUpdater -Name $name -Provider $provider -Target $target -Source $source
    } catch [System.Management.Automation.ValidationMetadataException] {
        Write-UpdaterLog "skipping ${name}: unknown updater provider '$provider'"
        return 2
    } catch {
        Write-UpdaterLog "${name} failed: $_"
        return 1
    }
}

function Invoke-Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Manifest
    )

    $result = @{
        Count = 0
        Status = 0
    }
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        return $result
    }

    Write-UpdaterLog "reading update manifest: $Manifest"
    try {
        $tools = @(ConvertFrom-ToolUpdateToml -Path $Manifest)
    } catch {
        Write-UpdaterLog "failed to read update manifest: $_"
        $result.Status = 2
        return $result
    }

    foreach ($tool in $tools) {
        $result.Count += 1
        $entryStatus = Invoke-ManifestTool -Tool $tool
        if ($entryStatus -ne 0) {
            $result.Status = $entryStatus
        }
    }

    return $result
}

function Invoke-UpdaterHooks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UpdaterDir
    )

    $result = @{
        Count = 0
        Status = 0
    }
    if (-not (Test-Path -LiteralPath $UpdaterDir -PathType Container)) {
        return $result
    }

    foreach ($updater in (Get-ChildItem -LiteralPath $UpdaterDir -File -Filter "*.ps1" | Sort-Object -Property Name)) {
        try {
            $result.Count += 1
            Write-UpdaterLog "running updater hook: $($updater.Name)"
            $currentShell = if ($IsWindows) {
                Join-Path -Path $PSHOME -ChildPath "pwsh.exe"
            } else {
                Join-Path -Path $PSHOME -ChildPath "pwsh"
            }

            & $currentShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $updater.FullName | ForEach-Object {
                [Console]::Out.WriteLine($_)
            }
            if ($LASTEXITCODE -ne 0) {
                Write-UpdaterLog "$($updater.Name) failed with exit code $LASTEXITCODE"
                $result.Status = $LASTEXITCODE
            }
        } catch {
            Write-UpdaterLog "$($updater.Name) failed: $_"
            $result.Status = 1
        }
    }

    return $result
}

$homeDir = $HOME
Add-PathPrefix -Paths @(
    (Join-Path -Path $homeDir -ChildPath ".bun\bin"),
    (Join-Path -Path $homeDir -ChildPath ".bun\install\global\node_modules\.bin"),
    (Join-Path -Path $homeDir -ChildPath ".cache\.bun\bin"),
    (Join-Path -Path $homeDir -ChildPath ".local\bin"),
    (Join-Path -Path $homeDir -ChildPath ".cargo\bin")
)

$manifest = if ($env:NIX_DOTFILES_TOOL_UPDATE_MANIFEST) {
    $env:NIX_DOTFILES_TOOL_UPDATE_MANIFEST
} else {
    Join-Path -Path $homeDir -ChildPath ".config\nix-dotfiles\tool-updates.toml"
}

$updaterDir = if ($env:NIX_DOTFILES_TOOL_UPDATERS_DIR) {
    $env:NIX_DOTFILES_TOOL_UPDATERS_DIR
} else {
    Join-Path -Path $homeDir -ChildPath ".config\nix-dotfiles\tool-updaters.d"
}

$mutex = [System.Threading.Mutex]::new($false, "nix-dotfiles-tool-update")
if (-not $mutex.WaitOne(0)) {
    Write-UpdaterLog "another tool updater is already running"
    exit 0
}

try {
    $status = 0
    Write-UpdaterLog "tool update started"

    $manifestResult = Invoke-Manifest -Manifest $manifest
    $hookResult = Invoke-UpdaterHooks -UpdaterDir $updaterDir

    if ($manifestResult.Count -eq 0 -and $hookResult.Count -eq 0) {
        Write-UpdaterLog "no tool updates configured; checked $manifest and $updaterDir"
    }
    if ($manifestResult.Status -ne 0) {
        $status = $manifestResult.Status
    }
    if ($hookResult.Status -ne 0) {
        $status = $hookResult.Status
    }

    Write-UpdaterLog "tool update finished with status $status"
} finally {
    [void] $mutex.ReleaseMutex()
    $mutex.Dispose()
}

exit $status
