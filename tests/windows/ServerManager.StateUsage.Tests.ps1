$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'state JSON usage' {
    BeforeEach {
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        $state = [pscustomobject]@{
            steamCmdPath = 'D:\SteamCMD'
            steamCmdLoginMode = 'account'
            rootConfigPath = 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
            steamCredentials = [pscustomobject]@{
                usernameBlob = 'userblob'
                passwordBlob = 'passblob'
            }
        }
        Save-JsonFile $script:stateConfigPath $state
    }

    It 'writes generated launch mod strings' {
        Set-GeneratedLaunchMods @('1559212036', '1750506510') @('3703219006')

        $launch = Get-GeneratedLaunchMods
        $launch.mod | Should Be '1559212036;1750506510;'
        $launch.serverMod | Should Be '3703219006;'

        $savedState = Get-JsonFile $script:stateConfigPath
        ($savedState.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($savedState.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false
    }

    It 'repairs empty generated launch state before writing both launch strings' {
        Save-JsonFile $script:stateConfigPath ([pscustomobject]@{
            steamCmdPath = 'D:\SteamCMD'
            rootConfigPath = 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'
            generatedLaunch = [pscustomobject]@{}
            trackedServers = @()
        })

        { Set-GeneratedLaunchMods @('1559212036') @('3703219006') } | Should Not Throw

        $launch = Get-GeneratedLaunchMods
        $launch.mod | Should Be '1559212036;'
        $launch.serverMod | Should Be '3703219006;'
    }

    It 'adds and clears tracked server records' {
        $process = [pscustomobject]@{
            Id = 1234
            StartTime = [datetime]'2026-04-11T12:00:00Z'
        }

        Add-TrackedServerRecord $process 'D:\SteamCMD\steamapps\common\DayZServer\DayZServer_x64.exe'
        (Get-TrackedServerRecords)[0].id | Should Be 1234

        $savedState = Get-JsonFile $script:stateConfigPath
        ($savedState.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($savedState.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false

        Clear-TrackedServerRecords
        (Get-TrackedServerRecords).Count | Should Be 0

        $savedState = Get-JsonFile $script:stateConfigPath
        ($savedState.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($savedState.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false
    }
}
