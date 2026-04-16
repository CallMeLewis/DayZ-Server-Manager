$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'server Steam authentication storage' {
    BeforeEach {
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        Save-JsonFile $script:stateConfigPath (New-DefaultStateConfig)
        Clear-SteamCmdSessionCredential
    }

    AfterEach {
        Clear-SteamCmdSessionCredential
    }

    It 'does not depend on ProtectedData for credential storage' {
        $scriptSource = Get-Content (Join-Path $PSScriptRoot '..\..\windows\Server_manager.ps1') -Raw

        $scriptSource -match 'System\.Security\.Cryptography\.ProtectedData' | Should Be $false
    }

    It 'saves and loads server Steam credentials with encrypted protection' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Save-SteamCmdCredential $credential

        $savedState = Get-JsonFile $script:stateConfigPath
        $savedState.serverSteamAuth.usernameBlob | Should Not BeNullOrEmpty
        $savedState.serverSteamAuth.passwordBlob | Should Not BeNullOrEmpty

        $loaded = Get-SavedSteamCmdCredential
        $loaded.UserName | Should Be 'dayz-owner'
        $loaded.GetNetworkCredential().Password | Should Be 'secret-pass'
    }

    It 'round trips a 128-character Steam password' {
        $longPassword = ('a' * 128)
        $securePassword = ConvertTo-SecureString $longPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Save-SteamCmdCredential $credential

        $loaded = Get-SavedSteamCmdCredential
        $loaded.GetNetworkCredential().Password | Should Be $longPassword
    }

    It 'prompts for one-time credentials without persisting them' {
        Mock Read-Host { 'dayz-owner' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { 'secret-pass' } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Save-StateConfig {}

        $credential = Prompt-SteamCmdCredential -Persist:$false

        $credential.UserName | Should Be 'dayz-owner'
        $credential.GetNetworkCredential().Password | Should Be 'secret-pass'
        Assert-MockCalled Save-StateConfig -Times 0
    }

    It 'prompts with -PendingSave without writing to disk and caches the new credential in the session var' {
        Mock Read-Host { 'dayz-owner-retry' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { 'new-secret' } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Save-StateConfig {}

        Clear-SteamCmdSessionCredential

        $credential = Prompt-SteamCmdCredential -Persist:$false -PendingSave

        $credential.UserName | Should Be 'dayz-owner-retry'
        $credential.GetNetworkCredential().Password | Should Be 'new-secret'
        Assert-MockCalled Save-StateConfig -Times 0
        (Get-SteamCmdSessionCredential).UserName | Should Be 'dayz-owner-retry'
    }

    It 'keeps one-time credentials available for the current session' {
        Mock Read-Host { 'dayz-owner' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { 'secret-pass' } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Save-StateConfig {}

        [void](Prompt-SteamCmdCredential -Persist:$false)

        Test-SteamCmdCredentialConfigured | Should Be $false
        $loginScriptPath = New-SteamCmdLoginScript -Credential (Get-SteamCmdSessionCredential) -Path (Join-Path $TestDrive 'login-test.tmp')
        $loginContent = (Get-Content -LiteralPath $loginScriptPath -Raw).Trim()
        $loginContent | Should Be 'login dayz-owner secret-pass'
        Remove-Item -LiteralPath $loginScriptPath -Force -ErrorAction SilentlyContinue
    }

    It 'prompts for credentials and saves them when requested' {
        $script:savedState = $null

        Mock Read-Host { 'dayz-owner' } -ParameterFilter { $Prompt -eq 'Steam account name' }
        Mock Read-Host { 'secret-pass' } -ParameterFilter { $Prompt -eq 'Steam password' }
        Mock Save-StateConfig {
            param($State)
            $script:savedState = $State
        }

        $credential = Prompt-SteamCmdCredential -Persist:$true

        $credential.UserName | Should Be 'dayz-owner'
        $credential.GetNetworkCredential().Password | Should Be 'secret-pass'
        Assert-MockCalled Save-StateConfig -Times 1
        $script:savedState.serverSteamAuth.usernameBlob | Should Not BeNullOrEmpty
        $script:savedState.serverSteamAuth.passwordBlob | Should Not BeNullOrEmpty
    }

    It 'clears saved credentials from state' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Save-SteamCmdCredential $credential
        Set-SteamCmdSessionCredential $credential

        Clear-SteamCmdCredential | Should Be $true

        Get-SavedSteamCmdCredential | Should BeNullOrEmpty
        Get-SteamCmdSessionCredential | Should BeNullOrEmpty
        Test-SteamCmdCredentialConfigured | Should Be $false
    }

    It 'clears an active session login even when nothing is saved' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Save-JsonFile $script:stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            generatedLaunch = [pscustomobject]@{
                mod = ''
                serverMod = ''
            }
            trackedServers = @()
        })
        Set-SteamCmdSessionCredential $credential

        Clear-SteamCmdCredential | Should Be $true

        Get-SteamCmdSessionCredential | Should BeNullOrEmpty
        Test-SteamCmdCredentialConfigured | Should Be $false
    }
}

Describe 'authenticated SteamCMD download flow' {
    BeforeEach {
        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed
        Set-SteamCmdRetryCredentialResolver $null
    }

    AfterEach {
        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed
        Set-SteamCmdRetryCredentialResolver $null
    }

    It 'prompts for a SteamCMD account before server update when none is saved' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = $null
        $script:capturedLoginScriptContent = $null
        $script:steamApp = 223350

        Mock Get-ActiveSteamCmdCredential { $null }
        Mock Read-Host { '1' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Prompt-SteamCmdCredential { $script:downloadCredential } -ParameterFilter { $Persist -eq $false }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContent = (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }

            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        Assert-MockCalled Prompt-SteamCmdCredential -Times 1 -ParameterFilter { $Persist -eq $false }
        $script:capturedSteamArgs[0] | Should Be '+runscript'
        $script:capturedLoginScriptContent | Should Be 'login dayz-owner secret-pass'
        $opArgs = @($script:capturedSteamArgs[2..($script:capturedSteamArgs.Count - 1)])
        ($opArgs -join ' ') | Should Be '+app_update 223350 validate +quit'
    }

    It 'saves the SteamCMD account when save securely is selected during server update' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = $null
        $script:capturedLoginScriptContent = $null
        $script:steamApp = 223350

        Mock Get-ActiveSteamCmdCredential { $null }
        Mock Read-Host { '2' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Prompt-SteamCmdCredential { $script:downloadCredential } -ParameterFilter { $Persist -eq $true }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContent = (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }

            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        Assert-MockCalled Prompt-SteamCmdCredential -Times 1 -ParameterFilter { $Persist -eq $true }
        $script:capturedSteamArgs[0] | Should Be '+runscript'
        $script:capturedLoginScriptContent | Should Be 'login dayz-owner secret-pass'
        $opArgs = @($script:capturedSteamArgs[2..($script:capturedSteamArgs.Count - 1)])
        ($opArgs -join ' ') | Should Be '+app_update 223350 validate +quit'
    }

    It 'uses authenticated login for server updates' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = $null
        $script:capturedLoginScriptContent = $null

        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350

        Mock Get-ActiveSteamCmdCredential { $script:downloadCredential }
        Mock Get-SavedSteamCmdCredential { $script:downloadCredential }
        Mock Resolve-SteamCmdDownloadCredential { $script:downloadCredential }
        Mock Prompt-SteamCmdCredential { $script:downloadCredential }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContent = (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }

            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        $script:capturedSteamArgs[0] | Should Be '+runscript'
        $script:capturedLoginScriptContent | Should Be 'login dayz-owner secret-pass'
        $opArgs = @($script:capturedSteamArgs[2..($script:capturedSteamArgs.Count - 1)])
        ($opArgs -join ' ') | Should Be '+app_update 223350 validate +quit'
    }

    It 'uses authenticated login for Workshop mod updates' {
        $script:folder = 'C:\SteamCMD'
        $script:appFolder = '\steamapps\common\DayZServer'
        $script:tempModList = Join-Path $TestDrive 'mods.txt'
        $script:tempModListServer = Join-Path $TestDrive 'serverMods.txt'
        $script:capturedSteamArgs = $null
        $script:capturedLoginScriptContent = $null

        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\workshop\content\221100\1559212036') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\keys') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\1559212036\keys') -Force | Out-Null

        function robocopy {
            param([string] $Source, [string] $Destination)
            $global:LASTEXITCODE = 0
            return 0
        }

        Mock Get-RootConfig {
            [pscustomobject]@{
                mods = @([pscustomobject]@{ workshopId = '1559212036'; name = 'CF'; url = '' })
                serverMods = @()
            }
        }
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        Mock Get-ActiveSteamCmdCredential { $script:downloadCredential }
        Mock Get-SavedSteamCmdCredential { $script:downloadCredential }
        Mock Resolve-SteamCmdDownloadCredential { $script:downloadCredential }
        Mock Prompt-SteamCmdCredential { $script:downloadCredential }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContent = (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }
            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }
        Mock Copy-Item {}
        Mock Remove-Item {}

        ModsUpdate | Out-Null

        $script:capturedSteamArgs[0] | Should Be '+runscript'
        $script:capturedLoginScriptContent | Should Be 'login dayz-owner secret-pass'
        $opArgs = @($script:capturedSteamArgs[2..($script:capturedSteamArgs.Count - 1)])
        ($opArgs -join ' ') | Should Be "+runscript $script:tempModList"

        Remove-Item function:robocopy -ErrorAction SilentlyContinue
    }

    It 'shows guided sign-in help when SteamCMD returns exit code 5' {
        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350
        $script:hostLines = @()

        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        Set-SteamCmdRetryCredentialResolver { $null }
        Mock Get-ActiveSteamCmdCredential { $script:downloadCredential }
        Mock Get-SavedSteamCmdCredential { $script:downloadCredential }
        Mock Resolve-SteamCmdDownloadCredential { $script:downloadCredential }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:hostLines += [string]$Object
            }
        }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)

            return [pscustomobject]@{
                ExitCode = 5
                Output = 'FAILED (Invalid Password)'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null
        $text = $script:hostLines -join "`n"

        $text | Should Match 'SteamCMD sign-in failed for the saved Steam account'
        $text | Should Match 'If Steam Guard is enabled, approve the sign-in in the Steam app and retry'
        $text | Should Match 'If Steam Guard uses email, SteamCMD will ask for the code in this same window after you enter your password'
        $text | Should Match 'Re-enter your Steam credentials if your password has changed'
    }

    It 'retries sign-in once after a failure and lets the user re-enter credentials' {
        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350
        $script:capturedSteamArgs = @()
        $script:capturedLoginScriptContents = @()

        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:initialCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:retryCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner-retry', $securePassword)

        Set-SteamCmdRetryCredentialResolver { $script:retryCredential }
        Mock Get-ActiveSteamCmdCredential { $script:initialCredential }
        Mock Resolve-SteamCmdDownloadCredential { $script:initialCredential }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)

            $script:capturedSteamArgs += ,@($Arguments)
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContents += (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }

            if ($script:capturedSteamArgs.Count -eq 1)
                {
                    return [pscustomobject]@{
                        ExitCode = 5
                        Output = 'FAILED (Invalid Password)'
                        StdOut = ''
                        StdErr = ''
                    }
                }

            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        $script:capturedSteamArgs.Count | Should Be 2
        $script:capturedLoginScriptContents[0] | Should Be 'login dayz-owner secret-pass'
        $script:capturedLoginScriptContents[1] | Should Be 'login dayz-owner-retry secret-pass'
        $opArgs = @($script:capturedSteamArgs[0][2..($script:capturedSteamArgs[0].Count - 1)])
        ($opArgs -join ' ') | Should Be '+app_update 223350 validate +quit'
    }

    It 'keeps the failed-login marker and saved credential when clear-and-reenter is canceled' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Save-SteamCmdCredential $credential
        Set-SteamCmdLastSignInFailed

        Mock Read-Host { '2' } -ParameterFilter { $Prompt -eq 'Select a retry option' }
        Mock Prompt-SteamCmdCredential { $null } -ParameterFilter { $Persist -eq $false }

        Request-SteamCmdRetryCredential | Should BeNullOrEmpty

        (Get-SavedSteamCmdCredential).UserName | Should Be 'dayz-owner'
        Test-SteamCmdLastSignInFailed | Should Be $true
    }

    It 'keeps the existing saved login when a clear-and-reenter retry still fails' {
        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350

        $oldPassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $oldCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $oldPassword)
        $newPassword = ConvertTo-SecureString 'new-secret' -AsPlainText -Force
        $newCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner-retry', $newPassword)
        $script:steamCmdAttempt = 0

        Save-SteamCmdCredential $oldCredential
        Set-SteamCmdRetryCredentialResolver {
            [pscustomobject]@{
                Credential = $newCredential
                SaveOnSuccess = $true
            }
        }
        Mock Get-ActiveSteamCmdCredential { $oldCredential }
        Mock Resolve-SteamCmdDownloadCredential { $oldCredential }
        Mock Invoke-SteamCmdCommand {
            $script:steamCmdAttempt++

            return [pscustomobject]@{
                ExitCode = 5
                Output = 'FAILED (Invalid Password)'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        (Get-SavedSteamCmdCredential).UserName | Should Be 'dayz-owner'
        $script:steamCmdAttempt | Should Be 2
    }

    It 'option 2 of the retry menu requests credentials with -PendingSave' {
        Mock Read-Host { '2' } -ParameterFilter { $Prompt -eq 'Select a retry option' }
        Mock Prompt-SteamCmdCredential {
            param([bool] $Persist = $true, [switch] $PendingSave)
            $securePassword = ConvertTo-SecureString 'new-secret' -AsPlainText -Force
            return New-Object System.Management.Automation.PSCredential ('dayz-owner-retry', $securePassword)
        } -ParameterFilter { $Persist -eq $false -and $PendingSave -eq $true }

        $result = Request-SteamCmdRetryCredential

        $result | Should Not BeNullOrEmpty
        $result.SaveOnSuccess | Should Be $true
        Assert-MockCalled Prompt-SteamCmdCredential -Scope It -Times 1 -ParameterFilter { $PendingSave -eq $true -and $Persist -eq $false }
    }

    It 'reports Saved status (not Session only) after a successful clear-and-reenter retry' {
        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        Save-JsonFile $script:stateConfigPath (New-DefaultStateConfig)

        $oldPassword = ConvertTo-SecureString 'old-secret' -AsPlainText -Force
        $oldCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $oldPassword)
        $newPassword = ConvertTo-SecureString 'new-secret' -AsPlainText -Force
        $global:retryNewCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner-retry', $newPassword)
        $global:steamCmdAttempt = 0
        $global:lastSavedRetryUserName = $null

        Save-SteamCmdCredential $oldCredential
        Clear-SteamCmdSessionCredential
        Clear-SteamCmdLastSignInFailed

        Set-SteamCmdRetryCredentialResolver {
            # Mirror Prompt-SteamCmdCredential -Persist:$false: it caches
            # the freshly entered credential in the session var as a side
            # effect, so the retry resolver does the same here.
            Set-SteamCmdSessionCredential $global:retryNewCredential
            return [pscustomobject]@{
                Credential = $global:retryNewCredential
                SaveOnSuccess = $true
            }
        }
        Mock Get-ActiveSteamCmdCredential { $oldCredential }
        Mock Resolve-SteamCmdDownloadCredential { $oldCredential }
        Mock Invoke-SteamCmdCommand {
            $global:steamCmdAttempt++
            if ($global:steamCmdAttempt -eq 1) {
                return [pscustomobject]@{
                    ExitCode = 5
                    Output = 'FAILED (Invalid Password)'
                    StdOut = ''
                    StdErr = ''
                }
            }
            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }
        Mock Save-SteamCmdCredential {
            param($Credential)
            $global:lastSavedRetryUserName = $Credential.UserName
        } -ParameterFilter { $Credential -and $Credential.UserName -eq 'dayz-owner-retry' }

        ServerUpdate | Out-Null

        $global:steamCmdAttempt | Should Be 2
        $global:lastSavedRetryUserName | Should Be 'dayz-owner-retry'
        Get-SteamCmdSessionCredential | Should BeNullOrEmpty

        Remove-Variable -Name retryNewCredential -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name steamCmdAttempt -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name lastSavedRetryUserName -Scope Global -ErrorAction SilentlyContinue
    }

    It 'restores the previous active login when a retry credential fails' {
        $script:folder = 'C:\SteamCMD'
        $script:steamApp = 223350

        $oldPassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $oldCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $oldPassword)
        $newPassword = ConvertTo-SecureString 'new-secret' -AsPlainText -Force
        $newCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner-retry', $newPassword)
        $script:steamCmdAttempt = 0

        Save-SteamCmdCredential $oldCredential
        Set-SteamCmdRetryCredentialResolver {
            Set-SteamCmdSessionCredential $newCredential
            return [pscustomobject]@{
                Credential = $newCredential
                SaveOnSuccess = $true
            }
        }
        Mock Get-ActiveSteamCmdCredential { $oldCredential }
        Mock Resolve-SteamCmdDownloadCredential { $oldCredential }
        Mock Invoke-SteamCmdCommand {
            $script:steamCmdAttempt++

            return [pscustomobject]@{
                ExitCode = 5
                Output = 'FAILED (Invalid Password)'
                StdOut = ''
                StdErr = ''
            }
        }

        ServerUpdate | Out-Null

        Get-SteamCmdSessionCredential | Should BeNullOrEmpty
        (Get-SavedSteamCmdCredential).UserName | Should Be 'dayz-owner'
        $script:steamCmdAttempt | Should Be 2
    }
}

Describe 'Steam login configuration seam' {
    It 'exposes Test-SteamCmdCredentialConfigured for the main status block' {
        Get-Command Test-SteamCmdCredentialConfigured -CommandType Function -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
    }

    It 'reports session-only login status separately from saved credentials' {
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Clear-SteamCmdLastSignInFailed
        Set-SteamCmdSessionCredential $credential

        Get-SteamCmdCredentialStatus | Should Be 'Session only'
    }

    It 'reports session-only login status when both saved and session credentials exist' {
        $savedPassword = ConvertTo-SecureString 'saved-pass' -AsPlainText -Force
        $savedCredential = New-Object System.Management.Automation.PSCredential ('saved-owner', $savedPassword)
        $sessionPassword = ConvertTo-SecureString 'session-pass' -AsPlainText -Force
        $sessionCredential = New-Object System.Management.Automation.PSCredential ('session-owner', $sessionPassword)

        Save-SteamCmdCredential $savedCredential
        Set-SteamCmdSessionCredential $sessionCredential

        Get-SteamCmdCredentialStatus | Should Be 'Session only'
    }

    It 'reports last sign-in failure in the credential status helper' {
        Clear-SteamCmdSessionCredential
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        Save-JsonFile $script:stateConfigPath ([pscustomobject]@{
            steamCmdPath = $null
            rootConfigPath = $rootConfigPath
            serverSteamAuth = [pscustomobject]@{
                usernameBlob = $null
                passwordBlob = $null
            }
            generatedLaunch = [pscustomobject]@{
                mod = ''
                serverMod = ''
            }
            trackedServers = @()
            lastSteamCmdSignInFailed = $true
        })

        Get-SteamCmdCredentialStatus | Should Be 'Last sign-in failed'
    }
}
