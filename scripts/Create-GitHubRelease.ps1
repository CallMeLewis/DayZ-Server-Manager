[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v?\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$')]
    [string] $Tag,

    [string] $Title,

    [string] $ReleaseDir,

    [string] $Repo,

    [switch] $Draft,

    [switch] $Prerelease,

    [switch] $SkipGenerateNotes,

    [switch] $ClobberAssets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string] $Name)

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-GhCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = & gh @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "gh exited with code $exitCode."
        }

        throw $message
    }

    return $output
}

function New-ReleaseArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    if (!(Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Source folder not found: $SourcePath"
    }

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }

    Compress-Archive -LiteralPath $SourcePath -DestinationPath $DestinationPath -CompressionLevel Optimal
}

function Test-ReleaseExists {
    param([Parameter(Mandatory = $true)][string] $ReleaseTag)

    $args = @('release', 'view', $ReleaseTag)
    if ($Repo) {
        $args += @('--repo', $Repo)
    }

    & gh @args *> $null
    return $LASTEXITCODE -eq 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsPath = Join-Path $repoRoot 'windows'
$linuxPath = Join-Path $repoRoot 'linux'

if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $repoRoot '.release'
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = "DayZ Server Manager $Tag"
}

if (!(Test-CommandExists 'gh')) {
    throw 'GitHub CLI (`gh`) is required but was not found in PATH.'
}

if (!(Test-Path -LiteralPath $windowsPath -PathType Container)) {
    throw "Windows folder not found: $windowsPath"
}

if (!(Test-Path -LiteralPath $linuxPath -PathType Container)) {
    throw "Linux folder not found: $linuxPath"
}

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

$windowsZip = Join-Path $ReleaseDir ("dayz-server-manager-windows-x64-{0}.zip" -f $Tag)
$linuxZip = Join-Path $ReleaseDir ("dayz-server-manager-linux-x64-{0}.zip" -f $Tag)

if ($PSCmdlet.ShouldProcess($windowsPath, "Create archive $windowsZip")) {
    New-ReleaseArchive -SourcePath $windowsPath -DestinationPath $windowsZip
}

if ($PSCmdlet.ShouldProcess($linuxPath, "Create archive $linuxZip")) {
    New-ReleaseArchive -SourcePath $linuxPath -DestinationPath $linuxZip
}

$windowsAsset = '{0}#Windows x64' -f $windowsZip
$linuxAsset = '{0}#Linux x64' -f $linuxZip

if ($PSCmdlet.ShouldProcess($Tag, 'Create or update GitHub release assets')) {
    if (Test-ReleaseExists -ReleaseTag $Tag) {
        $uploadArgs = @('release', 'upload', $Tag, $windowsAsset, $linuxAsset)
        if ($ClobberAssets) {
            $uploadArgs += '--clobber'
        }
        if ($Repo) {
            $uploadArgs += @('--repo', $Repo)
        }

        Invoke-GhCommand -Arguments $uploadArgs | Out-Null
        Write-Host "Uploaded assets to existing release $Tag."
    }
    else {
        $createArgs = @('release', 'create', $Tag, $windowsAsset, $linuxAsset, '--title', $Title)
        if (!$SkipGenerateNotes) {
            $createArgs += '--generate-notes'
        }
        if ($Draft) {
            $createArgs += '--draft'
        }
        if ($Prerelease) {
            $createArgs += '--prerelease'
        }
        if ($Repo) {
            $createArgs += @('--repo', $Repo)
        }

        Invoke-GhCommand -Arguments $createArgs | Out-Null
        Write-Host "Created release $Tag."
    }
}

Write-Host "Windows asset: $windowsZip"
Write-Host "Linux asset: $linuxZip"
