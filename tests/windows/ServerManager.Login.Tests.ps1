$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'SteamCMD login arguments' {
    It 'returns authenticated login arguments from saved credentials' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Set-SteamCmdSessionCredential $credential

        $args = Get-SteamCmdLoginArguments

        ($args -join ' ') | Should Be '+login dayz-owner secret-pass'

        Clear-SteamCmdSessionCredential
    }

    It 'returns saved credentials without prompting' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Mock Get-SavedSteamCmdCredential { $credential }
        Mock Prompt-SteamCmdCredential { throw 'Prompt-SteamCmdCredential should not be called when credentials are already saved.' }

        $loaded = Ensure-SteamCmdCredential

        $loaded.UserName | Should Be 'dayz-owner'
        $loaded.GetNetworkCredential().Password | Should Be 'secret-pass'
        Assert-MockCalled Prompt-SteamCmdCredential -Times 0
    }

    It 'returns null without prompting when no saved credentials exist' {
        Mock Get-SavedSteamCmdCredential { $null }
        Mock Prompt-SteamCmdCredential { throw 'Prompt-SteamCmdCredential should not be called when no saved credentials exist.' }

        Ensure-SteamCmdCredential | Should BeNullOrEmpty

        Assert-MockCalled Prompt-SteamCmdCredential -Times 0
    }

    It 'loads deprecated login keys and persists normalized state without them' {
        $stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        $script:stateConfigPath = $stateConfigPath
        $legacyState = [pscustomobject]@{
            steamCmdPath = 'D:\SteamCMD'
            steamCmdLoginMode = 'account'
            rootConfigPath = 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
            steamCredentials = [pscustomobject]@{ usernameBlob = 'userblob'; passwordBlob = 'passblob' }
        }
        Save-JsonFile $stateConfigPath $legacyState

        $state = Get-StateConfig
        $state.steamCmdPath | Should Be 'D:\SteamCMD'
        $state.rootConfigPath | Should Be 'D:\Coding\DayZ\Server Manager\windows\server-manager.config.json'
        $state.generatedLaunch.mod | Should Be ''
        @($state.trackedServers).Count | Should Be 0
        $state.serverSteamAuth.usernameBlob | Should Be $null
        $state.serverSteamAuth.passwordBlob | Should Be $null

        $savedState = Get-JsonFile $stateConfigPath
        ($savedState.PSObject.Properties.Name -contains 'steamCmdLoginMode') | Should Be $false
        ($savedState.PSObject.Properties.Name -contains 'steamCredentials') | Should Be $false
    }
}

Describe 'New-SteamCmdLoginScript' {
    It 'writes a login command to the specified file path' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $scriptPath = Join-Path $TestDrive 'login-test.tmp'

        $result = New-SteamCmdLoginScript -Credential $credential -Path $scriptPath

        $result | Should Be $scriptPath
        Test-Path -LiteralPath $scriptPath | Should Be $true
        $content = (Get-Content -LiteralPath $scriptPath -Raw).Trim()
        $content | Should Be 'login dayz-owner secret-pass'

        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }

    It 'creates parent directories if they do not exist' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $scriptPath = Join-Path $TestDrive 'subdir\login-test.tmp'

        $result = New-SteamCmdLoginScript -Credential $credential -Path $scriptPath

        Test-Path -LiteralPath $scriptPath | Should Be $true

        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }

    It 'does not expose credentials on the steamcmd command line' {
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = $null
        $script:steamApp = 223350

        Mock Resolve-SteamCmdDownloadCredential { $credential }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            return [pscustomobject]@{ ExitCode = 0; Output = 'Success'; StdOut = ''; StdErr = '' }
        }

        Invoke-SteamCmdAuthenticatedOperation -Operation 'test' -Arguments @('+quit')

        $argsString = $script:capturedSteamArgs -join ' '
        $argsString | Should Not Match 'secret-pass'
        $argsString | Should Match '\+runscript'
    }

    It 'is cleaned up after authenticated operation completes' {
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:steamApp = 223350

        Mock Resolve-SteamCmdDownloadCredential { $credential }
        Mock Invoke-SteamCmdCommand {
            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }

        Invoke-SteamCmdAuthenticatedOperation -Operation 'test' -Arguments @('+quit')

        Test-Path -LiteralPath $script:tempLoginScript | Should Be $false
    }
}

Describe 'Prompt-SteamCmdCredential persist behavior' {
    It 'reports Saved status (not Session only) immediately after saving credentials' {
        $stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        $script:stateConfigPath = $stateConfigPath
        Save-JsonFile $stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            generatedLaunch = [pscustomobject]@{ mod = ''; serverMod = '' }
            trackedServers = @()
        })

        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed

        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        Mock Read-Host {
            param($Prompt, [switch] $AsSecureString)
            if ($Prompt -eq 'Steam account name') { return 'dayz-owner' }
            if ($Prompt -eq 'Steam password') { return $securePassword }
        }

        Prompt-SteamCmdCredential -Persist:$true | Out-Null

        Get-SteamCmdSessionCredential | Should BeNullOrEmpty
        Get-SteamCmdCredentialStatus | Should Be 'Saved'

        Clear-SteamCmdSessionCredential
    }
}
