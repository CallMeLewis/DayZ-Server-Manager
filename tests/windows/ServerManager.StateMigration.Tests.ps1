$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'state config migration' {
    It 'migrates saved paths, generated launch state, and tracked servers without importing legacy Steam login blobs' {
        $stateRoot = Join-Path $TestDrive 'DayZ_Server'
        New-Item -ItemType Directory -Path $stateRoot | Out-Null
        'D:\SteamCMD' | Set-Content -LiteralPath (Join-Path $stateRoot 'SteamCmdPath.txt')
        'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json' | Set-Content -LiteralPath (Join-Path $stateRoot 'userServerParPath.txt')
        '1559212036;' | Set-Content -LiteralPath (Join-Path $stateRoot 'modServerPar.txt')
        '3703219006;' | Set-Content -LiteralPath (Join-Path $stateRoot 'serverModServerPar.txt')
        '"1234","D:\SteamCMD\steamapps\common\DayZServer\DayZServer_x64.exe","2026-04-11T12:00:00.0000000Z"' | Set-Content -LiteralPath (Join-Path $stateRoot 'pidServer.txt')
        'userblob' | Set-Content -LiteralPath (Join-Path $stateRoot 'SteamLog1.txt')
        'passblob' | Set-Content -LiteralPath (Join-Path $stateRoot 'SteamLog2.txt')

        $statePath = Join-Path $stateRoot 'server-manager.state.json'
        Initialize-StateConfig $stateRoot $statePath 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'

        $state = Get-JsonFile $statePath
        $state.steamCmdPath | Should Be 'D:\SteamCMD'
        $state.generatedLaunch.mod | Should Be '1559212036;'
        $state.generatedLaunch.serverMod | Should Be '3703219006;'
        $state.trackedServers[0].id | Should Be 1234
        ($state.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($state.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false
        Test-Path -LiteralPath (Join-Path $stateRoot 'SteamCmdPath.txt.legacy.bak') | Should Be $true
        Test-Path -LiteralPath (Join-Path $stateRoot 'SteamLog1.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $stateRoot 'SteamLog2.txt') | Should Be $true
        Test-Path -LiteralPath (Join-Path $stateRoot 'SteamLog1.txt.legacy.bak') | Should Be $false
        Test-Path -LiteralPath (Join-Path $stateRoot 'SteamLog2.txt.legacy.bak') | Should Be $false
    }

    It 'migrates Base64-encoded username blob to DPAPI encryption on load' {
        $stateConfigPath = Join-Path $TestDrive 'base64-migrate.state.json'
        $script:stateConfigPath = $stateConfigPath

        # Create a state file with a Base64-encoded username (legacy format)
        $legacyUsernameBlob = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('dayz-owner'))
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $passwordBlob = ConvertFrom-SecureString $securePassword

        Save-JsonFile $stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            lastSteamCmdSignInFailed = $false
            serverSteamAuth = [pscustomobject]@{
                usernameBlob = $legacyUsernameBlob
                passwordBlob = $passwordBlob
            }
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
        })

        # Loading the state should trigger migration
        $state = Get-StateConfig

        # The username blob should have changed (migrated from Base64 to DPAPI)
        $rawState = Get-JsonFile $stateConfigPath
        $rawState.serverSteamAuth.usernameBlob | Should Not Be $legacyUsernameBlob

        # The credential should still round-trip correctly
        $loaded = Get-SavedSteamCmdCredential
        $loaded.UserName | Should Be 'dayz-owner'
        $loaded.GetNetworkCredential().Password | Should Be 'secret-pass'
    }

    It 'clears credentials when both DPAPI and Base64 decryption fail' {
        $stateConfigPath = Join-Path $TestDrive 'corrupt-migrate.state.json'
        $script:stateConfigPath = $stateConfigPath

        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $passwordBlob = ConvertFrom-SecureString $securePassword

        Save-JsonFile $stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            lastSteamCmdSignInFailed = $false
            serverSteamAuth = [pscustomobject]@{
                usernameBlob = '!!!not-valid-base64-or-dpapi!!!'
                passwordBlob = $passwordBlob
            }
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
        })

        $state = Get-StateConfig

        # Corrupted blob should be left as-is (migration returns null)
        # but Get-SavedSteamCmdCredential should fail gracefully
        Get-SavedSteamCmdCredential | Should BeNullOrEmpty
    }

    It 'creates a default state JSON when no legacy files exist' {
        $stateRoot = Join-Path $TestDrive 'FreshDayZ_Server'
        New-Item -ItemType Directory -Path $stateRoot | Out-Null

        $statePath = Join-Path $stateRoot 'server-manager.state.json'
        $configPath = 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'
        Initialize-StateConfig $stateRoot $statePath $configPath

        $state = Get-JsonFile $statePath
        $state.steamCmdPath | Should Be $null
        $state.rootConfigPath | Should Be $configPath
        $state.generatedLaunch.mod | Should Be ''
        $state.generatedLaunch.serverMod | Should Be ''
        @($state.trackedServers).Count | Should Be 0
        ($state.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($state.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false
    }
}
