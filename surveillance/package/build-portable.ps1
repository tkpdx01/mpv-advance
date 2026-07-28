[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86', 'all')]
    [string]$Arch = 'all',
    [switch]$SkipSmokeTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SurveillanceRoot = Split-Path -Parent $PackageRoot
$RepoRoot = Split-Path -Parent $SurveillanceRoot
$CacheRoot = Join-Path $PackageRoot '.cache'
$DistRoot = Join-Path $PackageRoot 'dist'

$Dependencies = @{
    x64 = @{
        Url = 'https://downloads.sourceforge.net/project/mpv-player-windows/64bit/mpv-x86_64-20231015-git-78d4374.7z'
        Archive = 'mpv-win7-x64.7z'
        Sha256 = 'F64F2546BD0EA4952E1012F0C54B9FB9CCE766474BA4ED841AF30A104C85FAB4'
        Machine = 0x8664
    }
    x86 = @{
        Url = 'https://downloads.sourceforge.net/project/mpv-player-windows/32bit/mpv-i686-20231015-git-78d4374.7z'
        Archive = 'mpv-win7-x86.7z'
        Sha256 = '67A85AA1FE58BDCE58F49501C605FE595F88D5AF555329A239359320767F0C10'
        Machine = 0x014c
    }
}

function Assert-SafeChildPath([string]$Path) {
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\') + '\'
    $target = [IO.Path]::GetFullPath($Path)
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside package directory: $target"
    }
}

function Remove-SafeDirectory([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Assert-SafeChildPath $Path
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        return $reader.ReadUInt16()
    } finally {
        $stream.Dispose()
    }
}

function Get-Dependency([string]$TargetArch) {
    $dependency = $Dependencies[$TargetArch]
    $archive = Join-Path $CacheRoot $dependency.Archive
    $valid = $false
    if (Test-Path -LiteralPath $archive) {
        $valid = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $dependency.Sha256
    }
    if (-not $valid) {
        New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
        Write-Host "Downloading fixed Win7 mpv build for $TargetArch..."
        Invoke-WebRequest -UseBasicParsing -Uri $dependency.Url -OutFile $archive
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ne $dependency.Sha256) {
            throw "SHA-256 mismatch for $archive. Expected $($dependency.Sha256), got $actual"
        }
    }
    return $archive
}

function Expand-SevenZip([string]$Archive, [string]$Destination) {
    Remove-SafeDirectory $Destination
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($sevenZip) {
        & $sevenZip.Source x $Archive "-o$Destination" -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7z extraction failed: $Archive" }
        return
    }
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        & $tar.Source -xf $Archive -C $Destination
        if ($LASTEXITCODE -ne 0) { throw "tar extraction failed: $Archive" }
        return
    }
    throw 'Building requires 7z.exe or a bsdtar-compatible tar.exe.'
}

function Invoke-SmokeTest([string]$PackageDirectory, [string]$TargetArch) {
    $exe = Join-Path $PackageDirectory 'runtime\mpv.exe'
    $config = Join-Path $PackageDirectory 'portable_config'
    $sample = Join-Path $PackageDirectory 'samples\channel001.mp4'
    $log = Join-Path $PackageDirectory 'smoke-test.log'
    $arguments = @(
        "--config-dir=$config", '--vo=null', '--ao=null', '--force-window=no',
        '--idle=no', '--keep-open=no', '--frames=5', "--log-file=$log",
        '--msg-level=all=warn,surveillance=info',
        '--script-opts=surveillance-api_enabled=no,surveillance-single_view=yes,surveillance-smoke_test=yes',
        $sample
    )
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "Smoke test failed for $TargetArch with exit code $($process.ExitCode). See $log"
    }
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}

function Build-Package([string]$TargetArch) {
    $dependency = $Dependencies[$TargetArch]
    $archive = Get-Dependency $TargetArch
    $expanded = Join-Path $CacheRoot "expanded-$TargetArch"
    Expand-SevenZip $archive $expanded

    $mpvExe = Join-Path $expanded 'mpv.exe'
    if (-not (Test-Path -LiteralPath $mpvExe)) { throw "mpv.exe missing after extracting $archive" }
    $machine = Get-PeMachine $mpvExe
    if ($machine -ne $dependency.Machine) {
        throw ('Wrong PE architecture for {0}: expected 0x{1:X4}, got 0x{2:X4}' -f $TargetArch, $dependency.Machine, $machine)
    }

    $name = "mpv-advance-v1-win7-$TargetArch"
    $packageDirectory = Join-Path $DistRoot $name
    Remove-SafeDirectory $packageDirectory
    New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $packageDirectory 'runtime') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $packageDirectory 'licenses') | Out-Null

    Copy-Item -LiteralPath (Join-Path $expanded 'mpv.exe') -Destination (Join-Path $packageDirectory 'runtime\mpv.exe')
    Copy-Item -LiteralPath (Join-Path $expanded 'mpv.com') -Destination (Join-Path $packageDirectory 'runtime\mpv.com')
    Copy-Item -LiteralPath (Join-Path $expanded 'd3dcompiler_43.dll') -Destination (Join-Path $packageDirectory 'runtime\d3dcompiler_43.dll')
    if (Test-Path -LiteralPath (Join-Path $expanded 'mpv')) {
        Copy-Item -LiteralPath (Join-Path $expanded 'mpv') -Destination (Join-Path $packageDirectory 'runtime\mpv') -Recurse
    }

    Copy-Item -LiteralPath (Join-Path $SurveillanceRoot 'portable_config') -Destination $packageDirectory -Recurse
    Copy-Item -LiteralPath (Join-Path $SurveillanceRoot 'data') -Destination $packageDirectory -Recurse
    Copy-Item -LiteralPath (Join-Path $SurveillanceRoot 'samples') -Destination $packageDirectory -Recurse
    Copy-Item -LiteralPath (Join-Path $SurveillanceRoot 'start.cmd') -Destination (Join-Path $packageDirectory 'start.cmd')
    Copy-Item -LiteralPath (Join-Path $SurveillanceRoot 'PORTABLE_README.txt') -Destination (Join-Path $packageDirectory 'README.txt')
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $packageDirectory 'licenses\THIRD_PARTY_NOTICES.txt')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE.GPL') -Destination (Join-Path $packageDirectory 'licenses\LICENSE.GPL.txt')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE.LGPL') -Destination (Join-Path $packageDirectory 'licenses\LICENSE.LGPL.txt')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'Copyright') -Destination (Join-Path $packageDirectory 'licenses\mpv-Copyright.txt')

    $smokeStatus = if ($SkipSmokeTest) { 'skipped; real target-machine acceptance required' } else { 'passed' }
    $version = @(
        'mpv-advance V1',
        "Target: Windows 7 SP1 $TargetArch",
        'Mode: one window / one video stream',
        'Bundled mpv: v0.36.0-549-g78d43740 (2023-10-15)',
        "mpv archive SHA-256: $($dependency.Sha256)",
        "Smoke test: $smokeStatus"
    )
    [IO.File]::WriteAllLines((Join-Path $packageDirectory 'VERSION.txt'), $version, (New-Object Text.UTF8Encoding($true)))

    if (-not $SkipSmokeTest) { Invoke-SmokeTest $packageDirectory $TargetArch }

    New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
    $zip = Join-Path $DistRoot "$name.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $zip -CompressionLevel Optimal
    $zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    Write-Host "Built $zip"
    Write-Host "SHA256 $zipHash"
}

New-Item -ItemType Directory -Force -Path $CacheRoot, $DistRoot | Out-Null
$targets = if ($Arch -eq 'all') { @('x64', 'x86') } else { @($Arch) }
foreach ($target in $targets) { Build-Package $target }
