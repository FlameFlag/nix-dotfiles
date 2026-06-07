#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [ValidateSet("x86_64", "aarch64")]
    [string]$Architecture,

    [Parameter(Mandatory = $true)]
    [int]$Jobs
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
if ($PSVersionTable.PSVersion -ge [version]"7.3") {
    $PSNativeCommandUseErrorActionPreference = $true
}

$sdk = switch ($Architecture) {
    "x86_64" {
        @{
            Repo = "git-sdk-64"
            Msys = "MINGW64"
            Prefix = "mingw64"
        }
    }
    "aarch64" {
        @{
            Repo = "git-sdk-arm64"
            Msys = "CLANGARM64"
            Prefix = "clangarm64"
        }
    }
}

$workDir = Split-Path $SourceDir -Parent
$sdkDir = Join-Path $workDir "git-for-windows-sdk"
$sdkArchive = Join-Path $workDir "git-sdk-$Architecture-minimal.tar.gz"
$sdkUrl = "https://github.com/git-for-windows/$($sdk.Repo)/releases/download/ci-artifacts/git-sdk-$Architecture-minimal.tar.gz"

New-Item -ItemType Directory -Force $sdkDir | Out-Null
Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkArchive

& tar.exe -xzf $sdkArchive -C $sdkDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$installShimPath = Join-Path $sdkDir "usr\bin\install"
$installShim = @'
#!/bin/sh
set -e

mode=
create_dirs=false

while [ $# -gt 0 ]; do
	case "$1" in
	-d)
		create_dirs=true
		shift
		;;
	-m)
		mode="$2"
		shift 2
		;;
	-s)
		shift
		;;
	--)
		shift
		break
		;;
	-*)
		shift
		;;
	*)
		break
		;;
	esac
done

if [ "$create_dirs" = true ]; then
	mkdir -p "$@"
	if [ -n "$mode" ]; then
		chmod "$mode" "$@"
	fi
	exit 0
fi

if [ $# -lt 2 ]; then
	echo "install shim: missing file operand" >&2
	exit 1
fi

for arg do
	destination="$arg"
done

if [ $# -gt 2 ] || [ -d "$destination" ]; then
	mkdir -p "$destination"
	while [ $# -gt 1 ]; do
		cp "$1" "$destination/"
		if [ -n "$mode" ]; then
			chmod "$mode" "$destination/$(basename "$1")"
		fi
		shift
	done
else
	mkdir -p "$(dirname "$destination")"
	cp "$1" "$destination"
	if [ -n "$mode" ]; then
		chmod "$mode" "$destination"
	fi
fi
'@
Set-Content -Path $installShimPath -Value $installShim -NoNewline

$env:GIT_SOURCE_DIR = $SourceDir
$env:GIT_PREFIX = $Prefix
$env:MSYSTEM = $sdk.Msys
$env:CHERE_INVOKING = "1"
$env:LC_CTYPE = "C.UTF-8"
$env:PATH = "$sdkDir\$($sdk.Prefix)\bin;$sdkDir\usr\bin;$sdkDir\usr\bin\core_perl;$env:PATH"

$bashScript = @'
chmod +x /usr/bin/install &&
cd "$(cygpath -u "$GIT_SOURCE_DIR")" &&
make prefix="$(cygpath -u "$GIT_PREFIX")" NO_GETTEXT=YesPlease NO_TCLTK=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease NO_REGEX=NeedsStartEnd NO_INSTALL_HARDLINKS=YesPlease -j__JOBS__ install
'@
$bashScript = $bashScript.Replace("__JOBS__", $Jobs.ToString())

& "$sdkDir\usr\bin\bash.exe" -lc $bashScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

foreach ($runtimeDir in @(
        (Join-Path $Prefix "bin")
        (Join-Path $Prefix "libexec\git-core")
    )) {
    if (Test-Path $runtimeDir) {
        foreach ($runtimeDlls in @(
                (Join-Path $sdkDir "$($sdk.Prefix)\bin\*.dll")
                (Join-Path $sdkDir "usr\bin\*.dll")
            )) {
            Copy-Item -Force -Path $runtimeDlls -Destination $runtimeDir
        }
    }
}
