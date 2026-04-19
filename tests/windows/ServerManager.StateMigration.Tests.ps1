$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'state config migration' {
    BeforeEach {
        $script:originalVaultTarget = $script:credentialVaultTarget
        $script:credentialVaultTarget = "DayZServerManagerTest:$([guid]::NewGuid())"
    }

    AfterEach {
        try { Remove-CredentialVault -Target $script:credentialVaultTarget } catch { }
        $script:credentialVaultTarget = $script:originalVaultTarget
    }

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

    It 'migrates a Base64-encoded username blob from state.json into the Windows Credential Vault' {
        $stateConfigPath = Join-Path $TestDrive 'base64-migrate.state.json'
        $script:stateConfigPath = $stateConfigPath

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

        $state = Get-StateConfig

        $rawState = Get-JsonFile $stateConfigPath
        ($rawState.PSObject.Properties.Name -contains 'serverSteamAuth') | Should Be $false

        $vaultEntry = Read-CredentialVault -Target $script:credentialVaultTarget
        $vaultEntry | Should Not BeNullOrEmpty
        $vaultEntry.Username | Should Be 'dayz-owner'
        $vaultEntry.Password | Should Be 'secret-pass'

        $loaded = Get-SavedSteamCmdCredential
        $loaded.UserName | Should Be 'dayz-owner'
        $loaded.GetNetworkCredential().Password | Should Be 'secret-pass'
    }

    It 'migrates a DPAPI-encoded username blob from state.json into the Windows Credential Vault' {
        $stateConfigPath = Join-Path $TestDrive 'dpapi-migrate.state.json'
        $script:stateConfigPath = $stateConfigPath

        $secureUsername = ConvertTo-SecureString 'dayz-owner' -AsPlainText -Force
        $usernameBlob = ConvertFrom-SecureString $secureUsername
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $passwordBlob = ConvertFrom-SecureString $securePassword

        Save-JsonFile $stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            lastSteamCmdSignInFailed = $false
            serverSteamAuth = [pscustomobject]@{
                usernameBlob = $usernameBlob
                passwordBlob = $passwordBlob
            }
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
        })

        $state = Get-StateConfig

        $rawState = Get-JsonFile $stateConfigPath
        ($rawState.PSObject.Properties.Name -contains 'serverSteamAuth') | Should Be $false

        $vaultEntry = Read-CredentialVault -Target $script:credentialVaultTarget
        $vaultEntry.Username | Should Be 'dayz-owner'
        $vaultEntry.Password | Should Be 'secret-pass'
    }

    It 'leaves state.json intact when the legacy blob cannot be decoded' {
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

        $rawState = Get-JsonFile $stateConfigPath
        ($rawState.PSObject.Properties.Name -contains 'serverSteamAuth') | Should Be $true

        Read-CredentialVault -Target $script:credentialVaultTarget | Should BeNullOrEmpty
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
