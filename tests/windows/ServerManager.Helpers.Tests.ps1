$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Server manager guard helpers' {
    It 'rejects filesystem roots as removable SteamCMD folders' {
        Test-SafeSteamCmdFolderForRemoval 'D:\' | Should Be $false
    }

    It 'accepts a folder only when steamcmd.exe is present' {
        $root = Join-Path $TestDrive 'SteamCMD'
        New-Item -ItemType Directory -Path $root | Out-Null
        New-Item -ItemType File -Path (Join-Path $root 'steamcmd.exe') | Out-Null

        Test-SafeSteamCmdFolderForRemoval $root | Should Be $true
    }

    It 'normalizes single-line state file values' {
        $file = Join-Path $TestDrive 'path.txt'
        "D:\SteamCMD`r`n" | Set-Content $file

        Get-StateFileValue $file | Should Be 'D:\SteamCMD'
    }

    It 'uses the selected app for the server management menu title' {
        $script:steamApp = 223350
        Get-ServerManagementTitle | Should Be 'Stable Server Management'

        $script:steamApp = 1042420
        Get-ServerManagementTitle | Should Be 'Experimental Server Management'

        $script:steamApp = $null
        Get-ServerManagementTitle | Should Be 'Server Management'
    }

    It 'uses the embedded version in the main menu title' {
        Get-MainMenuTitle | Should Be ("DayZ Server Manager v$script:serverManagerVersion")
    }

    It 'resolves the current server directory from saved SteamCMD path and selected app folder' {
        Mock Get-StateConfig {
            return [pscustomobject]@{
                steamCmdPath = 'D:\SteamCMD'
            }
        }

        $script:appFolder = '\steamapps\common\DayZServer'

        Get-CurrentServerDirectory | Should Be 'D:\SteamCMD\steamapps\common\DayZServer'
    }

    It 'reports a running tracked server when a tracked process is still valid' {
        Mock Get-TrackedServerRecords {
            return @(
                [pscustomobject]@{
                    id = 1234
                    path = 'D:\SteamCMD\steamapps\common\DayZServer\DayZServer_x64.exe'
                    startTime = '2026-04-11T12:00:00.0000000Z'
                }
            )
        }

        Mock Get-TrackedDayZProcess {
            return [pscustomobject]@{ Id = 1234 }
        }

        Test-TrackedServerRunning | Should Be $true
    }

    It 'shows SteamCMD account status in the main status block' {
        $script:statusLines = @()

        Mock Test-TrackedServerRunning { $false }
        Mock Get-CurrentServerDirectory { 'C:\SteamCMD\steamapps\common\DayZServer' }
        Mock Get-SteamCmdCredentialStatus { 'Not configured' }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:statusLines += [string]$Object
            }
        }

        Show-MainMenuStatus

        ($script:statusLines -join "`n") | Should Match 'Account\s+: Not configured'
    }

    It 'shows SteamCMD account status as saved in the main status block' {
        $script:statusLines = @()

        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)

        Mock Test-TrackedServerRunning { $false }
        Mock Get-CurrentServerDirectory { 'C:\SteamCMD\steamapps\common\DayZServer' }
        Mock Get-SteamCmdCredentialStatus { 'Saved' }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:statusLines += [string]$Object
            }
        }

        Show-MainMenuStatus

        ($script:statusLines -join "`n") | Should Match 'Account\s+: Saved'
    }

    It 'shows SteamCMD account status as session only in the main status block' {
        $script:statusLines = @()

        Mock Test-TrackedServerRunning { $false }
        Mock Get-CurrentServerDirectory { 'C:\SteamCMD\steamapps\common\DayZServer' }
        Mock Get-SteamCmdCredentialStatus { 'Session only' }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:statusLines += [string]$Object
            }
        }

        Show-MainMenuStatus

        ($script:statusLines -join "`n") | Should Match 'Account\s+: Session only'
    }

    It 'shows SteamCMD account status as last sign-in failed in the main status block' {
        $script:statusLines = @()

        Mock Test-TrackedServerRunning { $false }
        Mock Get-CurrentServerDirectory { 'C:\SteamCMD\steamapps\common\DayZServer' }
        Mock Get-SteamCmdCredentialStatus { 'Last sign-in failed' }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:statusLines += [string]$Object
            }
        }

        Show-MainMenuStatus

        ($script:statusLines -join "`n") | Should Match 'Account\s+: Last sign-in failed'
    }

    It 'renders the active group inside the status block before the closing divider' {
        $script:statusLines = @()

        Mock Test-TrackedServerRunning { $false }
        Mock Get-CurrentServerDirectory { 'D:\SteamCMD\steamapps\common\DayZServer' }
        Mock Get-SteamCmdCredentialStatus { 'Saved' }
        Mock Get-RootConfig {
            [pscustomobject]@{
                activeGroup = 'Deerisle 5.9 Stable'
                mods = @(
                    [pscustomobject]@{ workshopId = '111'; name = 'A'; url = '' }
                    [pscustomobject]@{ workshopId = '222'; name = 'B'; url = '' }
                    [pscustomobject]@{ workshopId = '333'; name = 'C'; url = '' }
                    [pscustomobject]@{ workshopId = '444'; name = 'D'; url = '' }
                )
                serverMods = @(
                    [pscustomobject]@{ workshopId = '999'; name = 'S1'; url = '' }
                    [pscustomobject]@{ workshopId = '888'; name = 'S2'; url = '' }
                )
                modGroups = @(
                    [pscustomobject]@{
                        name = 'Deerisle 5.9 Stable'
                        mods = @('111', '222', '333', '444')
                        serverMods = @('999', '888')
                    }
                )
            }
        }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:statusLines += [string]$Object
            }
        }

        Show-MainMenuStatus

        ($script:statusLines -join "`n") | Should Match 'Account\s+: Saved\s+Active group\s+: Deerisle 5\.9 Stable\s+\(4 mods, 2 serverMods\)'
    }

    It 'renders the status block when showing the main menu' {
        $script:menuReadHostCalls = 0

        Mock Show-MenuHeader {}
        Mock Show-MainMenuStatus {}
        Mock ModManager_menu {}
        Mock Read-Host {
            $script:menuReadHostCalls++
            if ($script:menuReadHostCalls -eq 1) { return '8' }
            throw 'stop-menu-test'
        }

        try {
            Menu
        } catch {
            $_.Exception.Message | Should Be 'stop-menu-test'
        }

        Assert-MockCalled Show-MainMenuStatus -Times 1
    }

    It 'renders the updated main menu labels' {
        $script:lastPrompt = $null
        $script:menuReadHostCalls = 0
        $script:menuCollected = [System.Collections.ArrayList]::new()

        Mock Show-MenuHeader {}
        Mock Show-MainMenuStatus {}
        Mock ModManager_menu {}
        Mock Read-Host {
            param([string]$Prompt)

            $script:lastPrompt = $Prompt
            $script:menuReadHostCalls++
            if ($script:menuReadHostCalls -eq 1) { return '8' }
            throw 'stop-menu-test'
        }

        try {
            Menu | ForEach-Object { [void]$script:menuCollected.Add($_) }
        } catch {
            $_.Exception.Message | Should Be 'stop-menu-test'
        }
        $menuText = $script:menuCollected -join "`n"

        $menuText | Should Match '1\) Update server'
        $menuText | Should Match '2\) Update mods'
        $menuText | Should Match '4\) Stop server'
        $menuText | Should Match '5\) SteamCMD Account'
        $menuText | Should Match '6\) Config Transfer'
        $menuText | Should Match '7\) Manage mod groups'
        $menuText | Should Match '8\) Manage mods'
        $menuText | Should Match '9\) Remove / Uninstall'
        $menuText | Should Match '10\) Exit'
        $script:lastPrompt | Should Be 'Select an option'
    }

    It 'returns to the main menu without pausing after a successful start' {
        $script:menuReadHostCalls = 0

        Mock Show-MenuHeader {}
        Mock Show-MainMenuStatus {}
        Mock Pause-BeforeMenu {}
        Mock Server_menu { $script:lastServerActionSucceeded = $true }
        Mock Read-Host {
            $script:menuReadHostCalls++
            if ($script:menuReadHostCalls -eq 1) { return '3' }
            throw 'stop-menu-test'
        }

        try {
            Menu
        } catch {
            $_.Exception.Message | Should Be 'stop-menu-test'
        }

        Assert-MockCalled Pause-BeforeMenu -Times 0
    }

    It 'returns to the main menu without pausing after a successful stop' {
        $script:menuReadHostCalls = 0

        Mock Show-MenuHeader {}
        Mock Show-MainMenuStatus {}
        Mock Pause-BeforeMenu {}
        Mock ServerStop { $script:lastServerActionSucceeded = $true }
        Mock Read-Host {
            $script:menuReadHostCalls++
            if ($script:menuReadHostCalls -eq 1) { return '4' }
            throw 'stop-menu-test'
        }

        try {
            Menu
        } catch {
            $_.Exception.Message | Should Be 'stop-menu-test'
        }

        Assert-MockCalled Pause-BeforeMenu -Times 0
    }

    It 'still pauses after an unsuccessful stop' {
        $script:menuReadHostCalls = 0

        Mock Show-MenuHeader {}
        Mock Show-MainMenuStatus {}
        Mock Pause-BeforeMenu {}
        Mock ServerStop { $script:lastServerActionSucceeded = $false }
        Mock Read-Host {
            $script:menuReadHostCalls++
            if ($script:menuReadHostCalls -eq 1) { return '4' }
            throw 'stop-menu-test'
        }

        try {
            Menu
        } catch {
            $_.Exception.Message | Should Be 'stop-menu-test'
        }

        Assert-MockCalled Pause-BeforeMenu -Times 1
    }

    It 'preserves successful start state through the interactive start server menu flow' {
        $script:lastServerActionSucceeded = $false
        $script:select = $null
        $script:folder = 'D:\SteamCMD'
        $script:appFolder = '\steamapps\common\DayZServer'

        Mock Show-MenuHeader {}
        Mock Read-Host { return '1' }
        Mock Get-GeneratedLaunchMods {
            return [pscustomobject]@{
                mod = ''
                serverMod = ''
            }
        }
        Mock Test-Path { return $true }
        Mock Get-RootConfig { return [pscustomobject]@{ launchParameters = '-config=serverDZ.cfg' } }
        Mock Get-ConfiguredLaunchParameters { return '-config=serverDZ.cfg' }
        Mock Start-Process {
            return [pscustomobject]@{
                Id = 1234
                StartTime = [datetime]::Parse('2026-04-11T12:00:00Z')
            }
        }
        Mock Add-TrackedServerRecord {}
        Mock Start-Sleep {}

        Server_menu

        $script:lastServerActionSucceeded | Should Be $true
    }

}

Describe 'ServerDZ mission template' {
    It 'reads the template mission folder' {
        $text = 'template="empty.59.deerisle";'
        (Get-MissionFolderFromServerConfigText $text) | Should Be 'empty.59.deerisle'
    }

    It 'updates template when given a mission' {
        $text = 'template="empty.59.deerisle";'
        (Set-MissionFolderInServerConfigText $text 'empty.60.deerisle') |
            Should Match 'template="empty.60.deerisle"'
    }
}
