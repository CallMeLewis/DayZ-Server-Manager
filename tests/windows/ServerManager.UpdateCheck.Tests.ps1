$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'New-DefaultStateConfig updateCheck field' {
    It 'includes an empty updateCheck object with all keys present' {
        $state = New-DefaultStateConfig
        $state.PSObject.Properties.Name -contains 'updateCheck' | Should Be $true
        $state.updateCheck.latestVersion | Should Be ''
        $state.updateCheck.latestTag | Should Be ''
        $state.updateCheck.releaseUrl | Should Be ''
        $state.updateCheck.checkedAt | Should Be ''
        $state.updateCheck.lastAcknowledgedVersion | Should Be ''
    }
}

Describe 'Get-StateConfig backfill' {
    It 'adds updateCheck block when loading a state file missing the field' {
        $docFolder = Join-Path $TestDrive 'DayZ_Server'
        New-Item -ItemType Directory -Path $docFolder | Out-Null
        $script:stateConfigPath = Join-Path $docFolder 'server-manager.state.json'

        $legacyState = [pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $null
            lastSteamCmdSignInFailed = $false
            serverSteamAuth = [pscustomobject]@{ usernameBlob = $null; passwordBlob = $null }
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
        }
        $legacyState | ConvertTo-Json -Depth 6 | Out-File -FilePath $script:stateConfigPath -Encoding UTF8

        $state = Get-StateConfig

        $state.PSObject.Properties.Name -contains 'updateCheck' | Should Be $true
        $state.updateCheck.latestVersion | Should Be ''
        $state.updateCheck.lastAcknowledgedVersion | Should Be ''
    }
}
