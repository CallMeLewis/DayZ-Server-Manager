$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Resolve-LegacyFilePath' {
    It 'returns the path from a reference file when the referenced file exists' {
        $refFile = Join-Path $TestDrive 'modListPath.txt'
        $dataFile = Join-Path $TestDrive 'custom\mod_list.txt'
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'custom') -Force | Out-Null
        'test data' | Set-Content -LiteralPath $dataFile
        $dataFile | Set-Content -LiteralPath $refFile

        $result = Resolve-LegacyFilePath $refFile (Join-Path $TestDrive 'fallback.txt')

        $result.Path | Should Be $dataFile
        $result.Source | Should Be 'reference'
    }

    It 'returns the fallback path when the reference file does not exist' {
        $fallback = Join-Path $TestDrive 'fallback.txt'
        'fallback data' | Set-Content -LiteralPath $fallback

        $result = Resolve-LegacyFilePath (Join-Path $TestDrive 'nonexistent.txt') $fallback

        $result.Path | Should Be $fallback
        $result.Source | Should Be 'fallback'
    }

    It 'returns null when neither reference nor fallback exists' {
        $result = Resolve-LegacyFilePath (Join-Path $TestDrive 'nope.txt') (Join-Path $TestDrive 'also-nope.txt')

        $result | Should BeNullOrEmpty
    }

    It 'returns the fallback when the reference file points to a nonexistent path' {
        $refFile = Join-Path $TestDrive 'modListPath.txt'
        $fallback = Join-Path $TestDrive 'mod_list.txt'
        'D:\NonExistent\mod_list.txt' | Set-Content -LiteralPath $refFile
        'fallback data' | Set-Content -LiteralPath $fallback

        $result = Resolve-LegacyFilePath $refFile $fallback

        $result.Path | Should Be $fallback
        $result.Source | Should Be 'fallback'
    }

    It 'trims whitespace from the reference file content' {
        $refFile = Join-Path $TestDrive 'ref.txt'
        $dataFile = Join-Path $TestDrive 'data.txt'
        'test data' | Set-Content -LiteralPath $dataFile
        "  $dataFile  `r`n" | Set-Content -LiteralPath $refFile

        $result = Resolve-LegacyFilePath $refFile (Join-Path $TestDrive 'fallback.txt')

        $result.Path | Should Be $dataFile
        $result.Source | Should Be 'reference'
    }
}

Describe 'Initialize-RootConfig with path references' {
    It 'reads mod list from a path-reference location instead of the script folder' {
        $rootPath = Join-Path $TestDrive 'ScriptDir'
        $docPath = Join-Path $TestDrive 'Documents'
        $customPath = Join-Path $TestDrive 'CustomMods'
        $configPath = Join-Path $rootPath 'server-manager.config.json'

        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        New-Item -ItemType Directory -Path $docPath -Force | Out-Null
        New-Item -ItemType Directory -Path $customPath -Force | Out-Null

        # Path-reference file points to custom location
        (Join-Path $customPath 'mod_list.txt') | Set-Content -LiteralPath (Join-Path $docPath 'modListPath.txt')

        # Actual mod list at the custom location
        "#CF`n1559212036" | Set-Content -LiteralPath (Join-Path $customPath 'mod_list.txt')

        $report = Initialize-RootConfig $rootPath $configPath $docPath

        $config = Get-JsonFile $configPath
        @($config.mods).Count | Should Be 1
        $config.mods[0].workshopId | Should Be '1559212036'
        @($report).Count | Should BeGreaterThan 0
        @($report)[0].description | Should Match 'Client mod list'
    }

    It 'falls back to the script folder when no path-reference file exists' {
        $rootPath = Join-Path $TestDrive 'ScriptDir2'
        $docPath = Join-Path $TestDrive 'Documents2'
        $configPath = Join-Path $rootPath 'server-manager.config.json'

        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        New-Item -ItemType Directory -Path $docPath -Force | Out-Null

        "#TestMod`n99887766" | Set-Content -LiteralPath (Join-Path $rootPath 'mod_list.txt')

        $report = Initialize-RootConfig $rootPath $configPath $docPath

        $config = Get-JsonFile $configPath
        @($config.mods).Count | Should Be 1
        $config.mods[0].workshopId | Should Be '99887766'
    }

    It 'returns an empty array when JSON config already exists' {
        $rootPath = Join-Path $TestDrive 'ScriptDir3'
        $configPath = Join-Path $rootPath 'server-manager.config.json'

        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        '{}' | Set-Content -LiteralPath $configPath

        $report = Initialize-RootConfig $rootPath $configPath

        @($report).Count | Should Be 0
    }

    It 'backs up files at their resolved locations' {
        $rootPath = Join-Path $TestDrive 'ScriptDir4'
        $docPath = Join-Path $TestDrive 'Documents4'
        $customPath = Join-Path $TestDrive 'CustomDir4'
        $configPath = Join-Path $rootPath 'server-manager.config.json'

        New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
        New-Item -ItemType Directory -Path $docPath -Force | Out-Null
        New-Item -ItemType Directory -Path $customPath -Force | Out-Null

        $customModFile = Join-Path $customPath 'my_mods.txt'
        "#CF`n1559212036" | Set-Content -LiteralPath $customModFile
        $customModFile | Set-Content -LiteralPath (Join-Path $docPath 'modListPath.txt')

        Initialize-RootConfig $rootPath $configPath $docPath | Out-Null

        Test-Path -LiteralPath "$customModFile.legacy.bak" | Should Be $true
        Test-Path -LiteralPath (Join-Path $docPath 'modListPath.txt.legacy.bak') | Should Be $true
    }
}

Describe 'Initialize-StateConfig migration report' {
    It 'returns a report for each migrated state file' {
        $stateRoot = Join-Path $TestDrive 'StateDir'
        $statePath = Join-Path $stateRoot 'server-manager.state.json'
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

        'C:\SteamCMD' | Set-Content -LiteralPath (Join-Path $stateRoot 'SteamCmdPath.txt')
        '1559212036;' | Set-Content -LiteralPath (Join-Path $stateRoot 'modServerPar.txt')

        $script:stateConfigPath = $statePath
        $report = Initialize-StateConfig $stateRoot $statePath 'config.json'

        @($report).Count | Should Be 2
        @($report)[0].description | Should Match 'SteamCMD path'
        @($report)[1].description | Should Match 'mod launch string'
    }

    It 'returns an empty array when state JSON already exists' {
        $stateRoot = Join-Path $TestDrive 'StateDir2'
        $statePath = Join-Path $stateRoot 'server-manager.state.json'
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        '{}' | Set-Content -LiteralPath $statePath

        $report = Initialize-StateConfig $stateRoot $statePath 'config.json'

        @($report).Count | Should Be 0
    }
}

Describe 'Show-MigrationReport' {
    It 'does not produce output for an empty report' {
        Mock Read-Host {}

        Show-MigrationReport @()

        Assert-MockCalled Read-Host -Times 0
    }

    It 'displays migration details for a non-empty report' {
        $script:hostOutput = @()
        Mock Write-Host { param($Object) if ($null -ne $Object) { $script:hostOutput += [string]$Object } }
        Mock Read-Host { '' }
        Mock Test-InteractiveMenuMode { $true }

        $report = @(
            [pscustomobject]@{ fileName = 'mod_list.txt'; sourcePath = 'D:\Mods\mod_list.txt'; targetFile = 'config.json'; description = 'Client mod list (2 mods)' }
        )

        Show-MigrationReport $report

        $text = $script:hostOutput -join "`n"
        $text | Should Match 'Configuration Migrated'
        $text | Should Match 'Client mod list'
        $text | Should Match 'legacy.bak'
        $text | Should Match 'Steam credentials'
    }
}
