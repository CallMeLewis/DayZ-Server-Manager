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

Describe 'Test-UpdateCheckCacheFresh' {
    It 'returns false when checkedAt is empty' {
        $updateCheck = [pscustomobject]@{ latestVersion = ''; latestTag = ''; releaseUrl = ''; checkedAt = ''; lastAcknowledgedVersion = '' }
        Test-UpdateCheckCacheFresh $updateCheck (Get-Date) | Should Be $false
    }

    It 'returns true when checkedAt is within six hours of now' {
        $now = Get-Date '2026-04-16T12:00:00Z'
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T09:30:00Z'; lastAcknowledgedVersion = '' }
        Test-UpdateCheckCacheFresh $updateCheck $now | Should Be $true
    }

    It 'returns false when checkedAt is older than six hours' {
        $now = Get-Date '2026-04-16T12:00:00Z'
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T05:30:00Z'; lastAcknowledgedVersion = '' }
        Test-UpdateCheckCacheFresh $updateCheck $now | Should Be $false
    }
}

Describe 'Test-UpdateCheckShouldNotify' {
    It 'returns true when cached latest is newer than current and never acknowledged' {
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T12:00:00Z'; lastAcknowledgedVersion = '' }
        Test-UpdateCheckShouldNotify $updateCheck '1.1.0' | Should Be $true
    }

    It 'returns false when user already acknowledged this version' {
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T12:00:00Z'; lastAcknowledgedVersion = '1.2.0' }
        Test-UpdateCheckShouldNotify $updateCheck '1.1.0' | Should Be $false
    }

    It 'returns false when current version is already at or above latest' {
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T12:00:00Z'; lastAcknowledgedVersion = '' }
        Test-UpdateCheckShouldNotify $updateCheck '1.2.0' | Should Be $false
        Test-UpdateCheckShouldNotify $updateCheck '1.3.0' | Should Be $false
    }

    It 'returns false when latestVersion is empty' {
        $updateCheck = [pscustomobject]@{ latestVersion = ''; latestTag = ''; releaseUrl = ''; checkedAt = ''; lastAcknowledgedVersion = '' }
        Test-UpdateCheckShouldNotify $updateCheck '1.1.0' | Should Be $false
    }
}

Describe 'Test-UpdateCheckShouldShowIndicator' {
    It 'returns true when cached latest is newer than current regardless of ack' {
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T12:00:00Z'; lastAcknowledgedVersion = '1.2.0' }
        Test-UpdateCheckShouldShowIndicator $updateCheck '1.1.0' | Should Be $true
    }

    It 'returns false when current is equal or greater' {
        $updateCheck = [pscustomobject]@{ latestVersion = '1.2.0'; latestTag = 'v1.2.0'; releaseUrl = ''; checkedAt = '2026-04-16T12:00:00Z'; lastAcknowledgedVersion = '' }
        Test-UpdateCheckShouldShowIndicator $updateCheck '1.2.0' | Should Be $false
    }
}

Describe 'Set-UpdateCheckAcknowledged' {
    It 'writes lastAcknowledgedVersion equal to the supplied version' {
        $state = New-DefaultStateConfig
        $state.updateCheck.latestVersion = '1.2.0'
        Set-UpdateCheckAcknowledged $state '1.2.0'
        $state.updateCheck.lastAcknowledgedVersion | Should Be '1.2.0'
    }
}

Describe 'Merge-UpdateCheckResult' {
    It 'writes latestVersion, latestTag, releaseUrl, and checkedAt on success' {
        $state = New-DefaultStateConfig
        $now = Get-Date '2026-04-16T12:00:00Z'
        $result = [pscustomobject]@{
            currentVersion = '1.1.0'
            latestVersion = '1.2.0'
            latestTag = 'v1.2.0'
            releaseUrl = 'https://example.invalid/v1.2.0'
            updateAvailable = $true
            error = $null
        }
        Merge-UpdateCheckResult $state $result $now

        $state.updateCheck.latestVersion | Should Be '1.2.0'
        $state.updateCheck.latestTag | Should Be 'v1.2.0'
        $state.updateCheck.releaseUrl | Should Be 'https://example.invalid/v1.2.0'
        $state.updateCheck.checkedAt | Should Be '2026-04-16T12:00:00Z'
    }

    It 'only updates checkedAt when the result has an error' {
        $state = New-DefaultStateConfig
        $state.updateCheck.latestVersion = '1.2.0'
        $state.updateCheck.latestTag = 'v1.2.0'
        $state.updateCheck.releaseUrl = 'https://example.invalid/v1.2.0'
        $state.updateCheck.checkedAt = '2026-04-15T12:00:00Z'

        $now = Get-Date '2026-04-16T12:00:00Z'
        $result = [pscustomobject]@{
            currentVersion = '1.1.0'
            latestVersion = $null
            latestTag = $null
            releaseUrl = $null
            updateAvailable = $false
            error = 'network error'
        }
        Merge-UpdateCheckResult $state $result $now

        $state.updateCheck.latestVersion | Should Be '1.2.0'
        $state.updateCheck.checkedAt | Should Be '2026-04-16T12:00:00Z'
    }

    It 'resets lastAcknowledgedVersion when the latest version changes' {
        $state = New-DefaultStateConfig
        $state.updateCheck.latestVersion = '1.2.0'
        $state.updateCheck.lastAcknowledgedVersion = '1.2.0'

        $now = Get-Date '2026-04-16T12:00:00Z'
        $result = [pscustomobject]@{
            currentVersion = '1.1.0'
            latestVersion = '1.3.0'
            latestTag = 'v1.3.0'
            releaseUrl = 'https://example.invalid/v1.3.0'
            updateAvailable = $true
            error = $null
        }
        Merge-UpdateCheckResult $state $result $now

        $state.updateCheck.latestVersion | Should Be '1.3.0'
        $state.updateCheck.lastAcknowledgedVersion | Should Be ''
    }
}

Describe 'Format-UpdateCheckNoticeLines' {
    It 'lists current, latest, and release URL' {
        $lines = Format-UpdateCheckNoticeLines '1.1.0' '1.2.0' 'https://example.invalid/v1.2.0'
        ($lines -join "`n") | Should Match '1\.1\.0'
        ($lines -join "`n") | Should Match '1\.2\.0'
        ($lines -join "`n") | Should Match 'https://example\.invalid/v1\.2\.0'
        ($lines -join "`n") | Should Match 'Press Enter to continue'
    }

    It 'omits the URL line when releaseUrl is empty' {
        $lines = Format-UpdateCheckNoticeLines '1.1.0' '1.2.0' ''
        ($lines -join "`n") | Should Not Match 'https?://'
    }
}

Describe 'Format-UpdateCheckIndicator' {
    It 'formats the indicator string when an update is available' {
        Format-UpdateCheckIndicator '1.1.0' '1.2.0' | Should Be '* Update available: v1.2.0 (current v1.1.0)'
    }

    It 'returns empty when latest is blank' {
        Format-UpdateCheckIndicator '1.1.0' '' | Should Be ''
    }
}
