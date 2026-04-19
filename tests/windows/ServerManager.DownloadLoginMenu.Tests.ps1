$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'SteamCMD account menu contract' {
    BeforeEach {
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        Save-JsonFile $script:stateConfigPath (New-DefaultStateConfig)
        $script:originalVaultTarget = $script:credentialVaultTarget
        $script:credentialVaultTarget = "DayZServerManagerTest:$([guid]::NewGuid())"
        Clear-SteamCmdCredential
        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed
    }

    AfterEach {
        Clear-SteamCmdCredential
        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed
        $script:credentialVaultTarget = $script:originalVaultTarget
    }

    It 'isolates credential operations from the production vault target' {
        $script:credentialVaultTarget | Should Match '^DayZServerManagerTest:'
    }

    It 'exposes a dedicated DownloadLogin_menu entry point' {
        Get-Command DownloadLogin_menu -CommandType Function -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
    }

    It 'describes why the SteamCMD account is needed and the available options' {
        Mock Show-MenuHeader {}
        Mock Menu {}
        Mock Read-Host { '4' }

        $menuOutput = @(DownloadLogin_menu)

        ($menuOutput -join "`n") | Should Match 'SteamCMD uses this account for DayZ server and mod downloads'
        ($menuOutput -join "`n") | Should Match 'Credentials are encrypted for the current Windows user'
        ($menuOutput -join "`n") | Should Match 'Using this account once does not save your credentials'
        ($menuOutput -join "`n") | Should Match '1\) Use account once'
        ($menuOutput -join "`n") | Should Match '2\) Save account securely'
        ($menuOutput -join "`n") | Should Match '3\) Clear saved account'
        ($menuOutput -join "`n") | Should Match '4\) Back to Main Menu'
    }

    It 'starts a one-time Steam login prompt when option 1 is selected' {
        Mock Show-MenuHeader {}
        Mock Read-Host { '1' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Read-Host { 'dayz-owner' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { ConvertTo-SecureString 'secret-pass' -AsPlainText -Force } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Pause-BeforeMenu {}
        Mock Menu {}

        [void](DownloadLogin_menu)

        Test-SteamCmdCredentialConfigured | Should Be $false
        $script:steamCmdLoginArgs = Get-SteamCmdLoginArguments
        ($script:steamCmdLoginArgs -join ' ') | Should Be '+login dayz-owner secret-pass'
    }

    It 'starts a saved Steam login prompt when option 2 is selected' {
        Mock Show-MenuHeader {}
        Mock Read-Host { '2' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Read-Host { 'dayz-owner' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { ConvertTo-SecureString 'secret-pass' -AsPlainText -Force } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Pause-BeforeMenu {}
        Mock Menu {}

        [void](DownloadLogin_menu)

        Test-SteamCmdCredentialConfigured | Should Be $true
        (Get-SavedSteamCmdCredential).UserName | Should Be 'dayz-owner'
    }

    It 'returns straight to the main menu without pausing when option 4 is selected' {
        Mock Show-MenuHeader {}
        Mock Read-Host { '4' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Pause-BeforeMenu {}

        [void](DownloadLogin_menu)

        Assert-MockCalled Pause-BeforeMenu -Scope It -Times 0
    }

    It 'clears the saved login when requested from the menu' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        Save-SteamCmdCredential $credential

        Mock Show-MenuHeader {}
        Mock Read-Host { '3' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Set-SteamCmdSessionCredential $credential
        Mock Pause-BeforeMenu {}
        Mock Menu {}

        [void](DownloadLogin_menu)

        Get-SavedSteamCmdCredential | Should BeNullOrEmpty
        Get-SteamCmdSessionCredential | Should BeNullOrEmpty
    }
}
