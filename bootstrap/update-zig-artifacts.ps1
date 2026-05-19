#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $IndexUrl = 'https://ziglang.org/download/index.json',
    [string] $MirrorBase = 'https://zigmirror.com',
    [string] $SourceQuery = 'source=nix-dotfiles-bootstrap',
    [string] $ArtifactsFile
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-ScriptDir {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    return Split-Path -Parent $PSCommandPath
}

function Get-ArtifactLine {
    param(
        [Parameter(Mandatory)]
        [psobject] $Index,

        [Parameter(Mandatory)]
        [string] $Target,

        [Parameter(Mandatory)]
        [string] $MirrorBase,

        [Parameter(Mandatory)]
        [string] $SourceQuery
    )

    $artifactProperty = $Index.master.PSObject.Properties[$Target]
    if (-not $artifactProperty) {
        throw "Missing .master.${Target} in Zig download index."
    }
    $artifact = $artifactProperty.Value

    $artifactUri = [uri] $artifact.tarball
    $fileName = Split-Path -Leaf $artifactUri.AbsolutePath
    $url = ('{0}/{1}?{2}' -f $MirrorBase.TrimEnd('/'), $fileName, $SourceQuery)
    return [pscustomobject] @{
        Version = [string] $Index.master.version
        Target  = $Target
        Url     = $url
        Sha256  = [string] $artifact.shasum
    }
}

function Format-ZigArtifactTable {
    param(
        [Parameter(Mandatory)]
        [psobject[]] $Rows
    )

    $allRows = @(
        [pscustomobject] @{
            Version = '#version'
            Target  = 'target'
            Url     = 'url'
            Sha256  = 'sha256'
        }
        $Rows
    )
    $versionWidth = ($allRows | ForEach-Object { $_.Version.Length } | Measure-Object -Maximum).Maximum
    $targetWidth = ($allRows | ForEach-Object { $_.Target.Length } | Measure-Object -Maximum).Maximum
    $urlWidth = ($allRows | ForEach-Object { $_.Url.Length } | Measure-Object -Maximum).Maximum
    $rowFormat = '{0,-' + $versionWidth + '}  {1,-' + $targetWidth + '}  {2,-' + $urlWidth + '}  {3}'

    $formattedRows = @(
        $rowFormat -f $allRows[0].Version, $allRows[0].Target, $allRows[0].Url, $allRows[0].Sha256
    )
    foreach ($row in $Rows) {
        $formattedRows += ($rowFormat -f $row.Version, $row.Target, $row.Url, $row.Sha256)
    }

    return $formattedRows
}

$scriptDir = Get-ScriptDir
if ([string]::IsNullOrWhiteSpace($ArtifactsFile)) {
    $ArtifactsFile = Join-Path $scriptDir 'zig-artifacts.tsv'
}

$oldProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    $index = Invoke-RestMethod -Uri $IndexUrl
}
finally {
    $ProgressPreference = $oldProgressPreference
}

$version = [string] $index.master.version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Missing .master.version in ${IndexUrl}."
}

$artifactRows = @(
    Get-ArtifactLine -Index $index -Target 'aarch64-macos' -MirrorBase $MirrorBase -SourceQuery $SourceQuery
    Get-ArtifactLine -Index $index -Target 'x86_64-linux' -MirrorBase $MirrorBase -SourceQuery $SourceQuery
    Get-ArtifactLine -Index $index -Target 'aarch64-linux' -MirrorBase $MirrorBase -SourceQuery $SourceQuery
    Get-ArtifactLine -Index $index -Target 'x86_64-windows' -MirrorBase $MirrorBase -SourceQuery $SourceQuery
)
$lines = Format-ZigArtifactTable -Rows $artifactRows
Set-Content -LiteralPath $ArtifactsFile -Value $lines -Encoding ascii

Write-Output "updated bootstrap Zig artifacts to ${version}"
