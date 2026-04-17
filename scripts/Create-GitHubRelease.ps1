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

function Copy-ReleaseItem {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $StagingRoot
    )

    if (!(Test-Path -LiteralPath $Source)) {
        throw "Source not found: $Source"
    }

    $leaf = Split-Path $Source -Leaf
    $destination = Join-Path $StagingRoot $leaf

    if (Test-Path -LiteralPath $Source -PathType Container) {
        Copy-Item -LiteralPath $Source -Destination $destination -Recurse -Force

        Get-ChildItem -LiteralPath $destination -Recurse -Directory -Filter '__pycache__' -Force |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

        Get-ChildItem -LiteralPath $destination -Recurse -File -Filter '*.pyc' -Force |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $destination -Force
    }
}

function New-ReleaseArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $SourcePaths,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }

    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dayz-release-{0}" -f [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    try {
        foreach ($source in $SourcePaths) {
            Copy-ReleaseItem -Source $source -StagingRoot $stagingRoot
        }

        $contents = Get-ChildItem -LiteralPath $stagingRoot -Force | ForEach-Object { $_.FullName }
        Compress-Archive -LiteralPath $contents -DestinationPath $DestinationPath -CompressionLevel Optimal
    }
    finally {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ReleaseExists {
    param([Parameter(Mandatory = $true)][string] $ReleaseTag)

    $viewArgs = @('release', 'view', $ReleaseTag)
    if ($Repo) {
        $viewArgs += @('--repo', $Repo)
    }

    # Relax strict ErrorAction so gh's "release not found" stderr doesn't raise a terminating error.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $null = & gh @viewArgs 2>&1
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
    return $LASTEXITCODE -eq 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsPath = Join-Path $repoRoot 'windows'
$linuxPath = Join-Path $repoRoot 'linux'
$dayzManagerPath = Join-Path $repoRoot 'dayz_manager'
$readmePath = Join-Path $repoRoot 'README.md'
$steamCredentialsPath = Join-Path $repoRoot 'STEAMCMD-CREDENTIALS.md'

if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $repoRoot '.release'
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = "DayZ Server Manager $Tag"
}

if (!(Test-CommandExists 'gh')) {
    throw 'GitHub CLI (`gh`) is required but was not found in PATH.'
}

foreach ($required in @($windowsPath, $linuxPath, $dayzManagerPath, $readmePath)) {
    if (!(Test-Path -LiteralPath $required)) {
        throw "Required release source not found: $required"
    }
}

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

$windowsZip = Join-Path $ReleaseDir ("dayz-server-manager-windows-x64-{0}.zip" -f $Tag)
$linuxZip = Join-Path $ReleaseDir ("dayz-server-manager-linux-x64-{0}.zip" -f $Tag)

$windowsSources = @($windowsPath, $dayzManagerPath, $readmePath)
if (Test-Path -LiteralPath $steamCredentialsPath) {
    $windowsSources += $steamCredentialsPath
}

$linuxSources = @($linuxPath, $dayzManagerPath, $readmePath)

if ($PSCmdlet.ShouldProcess($windowsZip, "Create Windows archive")) {
    New-ReleaseArchive -SourcePaths $windowsSources -DestinationPath $windowsZip
}

if ($PSCmdlet.ShouldProcess($linuxZip, "Create Linux archive")) {
    New-ReleaseArchive -SourcePaths $linuxSources -DestinationPath $linuxZip
}

$windowsAsset = $windowsZip
$linuxAsset = $linuxZip

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
