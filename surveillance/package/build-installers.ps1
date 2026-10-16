[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86', 'all')]
    [string]$Arch = 'all',
    [string]$InnoSetupCompiler = '',
    [switch]$SkipPortableBuild,
    [switch]$SkipX86SmokeTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DistRoot = Join-Path $PackageRoot 'dist'
$PortableBuilder = Join-Path $PackageRoot 'build-portable.ps1'
$InstallerScript = Join-Path $PackageRoot 'installer.iss'
$LandingPage = Join-Path $PackageRoot 'index.html'
$ChineseLanguageUrl = 'https://raw.githubusercontent.com/jrsoftware/issrc/935fdb378b059eebf460574d5592b1a439a671ab/Files/Languages/ChineseSimplified.isl'
$ChineseLanguageSha256 = '6753BE2C5E2740D859900FD902824DB2EC568DA5C5B52486524C9762D778B0B0'

function Resolve-InnoSetupCompiler {
    $candidates = @()
    if ($InnoSetupCompiler) { $candidates += $InnoSetupCompiler }
    $candidates += (Join-Path $PackageRoot '.cache\inno-6.4.3\ISCC.exe')
    $candidates += (Join-Path $PackageRoot '.cache\inno\ISCC.exe')
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Inno Setup 6 compiler not found. Install Inno Setup or pass -InnoSetupCompiler C:\path\to\ISCC.exe.'
}

function Ensure-ChineseLanguageFile([string]$CompilerPath) {
    $languageDirectory = Join-Path (Split-Path -Parent $CompilerPath) 'Languages'
    $languageFile = Join-Path $languageDirectory 'ChineseSimplified.isl'
    $compatibilityFile = Join-Path $languageDirectory 'ChineseSimplified-6.4.isl'
    $valid = $false
    if (Test-Path -LiteralPath $languageFile) {
        $valid = (Get-FileHash -LiteralPath $languageFile -Algorithm SHA256).Hash -eq $ChineseLanguageSha256
    }
    if (-not $valid) {
        New-Item -ItemType Directory -Force -Path $languageDirectory | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri $ChineseLanguageUrl -OutFile $languageFile
        $actual = (Get-FileHash -LiteralPath $languageFile -Algorithm SHA256).Hash
        if ($actual -ne $ChineseLanguageSha256) {
            throw "Chinese language file SHA-256 mismatch. Expected $ChineseLanguageSha256, got $actual"
        }
    }

    $unsupportedMessages = @(
        'DownloadingLabel2', 'ExtractingLabel',
        'ArchiveIncorrectPassword', 'ArchiveIsCorrupted', 'ArchiveUnsupportedFormat',
        'RetryCancelSelectAction', 'RetryCancelRetry', 'RetryCancelCancel',
        'StatusDownloadFiles', 'SourceVerificationFailed',
        'VerificationSignatureDoesntExist', 'VerificationSignatureInvalid',
        'VerificationKeyNotFound', 'VerificationFileNameIncorrect',
        'VerificationFileTagIncorrect', 'VerificationFileSizeIncorrect',
        'VerificationFileHashIncorrect', 'ErrorDownloading', 'ErrorExtracting'
    )
    $compatibilityLines = New-Object Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $languageFile -Encoding UTF8)) {
        $messageName = if ($line -match '^([^;][^=]+)=') { $Matches[1].Trim() } else { '' }
        if ($unsupportedMessages -contains $messageName) { continue }
        if ($line -eq '[CustomMessages]') {
            $compatibilityLines.Add('DownloadingLabel=正在下载附加文件...')
            $compatibilityLines.Add('ErrorFileHash1=文件哈希校验失败：%1')
            $compatibilityLines.Add('ErrorFileHash2=文件哈希无效：应为 %1，实际为 %2')
            $compatibilityLines.Add('ExtractionLabel=正在提取附加文件...')
            $compatibilityLines.Add('')
        }
        $compatibilityLines.Add($line)
    }
    [IO.File]::WriteAllLines(
        $compatibilityFile,
        $compatibilityLines,
        (New-Object Text.UTF8Encoding($true)))
}

function Invoke-PortableBuild([string]$TargetArch) {
    $arguments = @{ Arch = $TargetArch }
    if ($TargetArch -eq 'x86' -and $SkipX86SmokeTest) {
        $arguments.SkipSmokeTest = $true
    }
    & $PortableBuilder @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Portable package build failed for $TargetArch with exit code $LASTEXITCODE"
    }
}

$targets = if ($Arch -eq 'all') { @('x64', 'x86') } else { @($Arch) }
if (-not $SkipPortableBuild) {
    foreach ($target in $targets) { Invoke-PortableBuild $target }
}

$compiler = Resolve-InnoSetupCompiler
Ensure-ChineseLanguageFile $compiler
foreach ($target in $targets) {
    & $compiler "/DTargetArch=$target" $InstallerScript
    if ($LASTEXITCODE -ne 0) {
        throw "Installer build failed for $target with exit code $LASTEXITCODE"
    }

    $bitness = if ($target -eq 'x64') { '64bit' } else { '32bit' }
    $installer = Join-Path $DistRoot "mpv-advance-v1-win7-$bitness-setup.exe"
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "Installer output is missing: $installer"
    }
    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
    Write-Host "Built $installer"
    Write-Host "SHA256 $hash"
}

if (-not (Test-Path -LiteralPath $LandingPage)) {
    throw "Offline landing page is missing: $LandingPage"
}
Copy-Item -LiteralPath $LandingPage -Destination (Join-Path $DistRoot 'index.html') -Force
Write-Host "Offline landing page: $(Join-Path $DistRoot 'index.html')"
