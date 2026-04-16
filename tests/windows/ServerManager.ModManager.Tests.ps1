$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Mod Manager helpers' {
    It 'extracts workshop ids from URLs and raw ids' {
        Get-WorkshopIdFromInput 'https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036' | Should Be '1559212036'
        Get-WorkshopIdFromInput '3703219006' | Should Be '3703219006'
    }

    It 'adds a client mod only once' {
        $config = [pscustomobject]@{ launchParameters = ''; mods = @(); serverMods = @() }

        Add-WorkshopModToConfig $config 'mods' '1559212036' 'CF' 'https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036'
        Add-WorkshopModToConfig $config 'mods' '1559212036' 'CF' 'https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036'

        @($config.mods).Count | Should Be 1
        $config.mods[0].name | Should Be 'CF'
    }

    It 'removes mods from both lists' {
        $config = [pscustomobject]@{
            launchParameters = ''
            mods = @([pscustomobject]@{ name = 'CF'; workshopId = '1559212036'; url = '' })
            serverMods = @([pscustomobject]@{ name = 'Fix'; workshopId = '3703219006'; url = '' })
        }

        Remove-WorkshopModFromConfig $config '1559212036'

        @($config.mods).Count | Should Be 0
        @($config.serverMods).Count | Should Be 1
    }

    It 'moves a mod between client and server lists' {
        $config = [pscustomobject]@{
            launchParameters = ''
            mods = @([pscustomobject]@{ name = 'Fix'; workshopId = '3703219006'; url = '' })
            serverMods = @()
        }

        Move-WorkshopModInConfig $config '3703219006' 'serverMods'

        @($config.mods).Count | Should Be 0
        @($config.serverMods).Count | Should Be 1
        $config.serverMods[0].workshopId | Should Be '3703219006'
    }

    It 'rejects non-ID remove input before any path checks or deletes' {
        $script:readHostResponses = @('2', '..\..\Windows', '5')
        $script:readHostIndex = 0
        $script:folder = $null

        Mock Show-MenuHeader {}
        Mock SteamCMDFolder { $script:folder = Join-Path $TestDrive 'SteamCMD' }
        Mock Get-StateConfig {
            [pscustomobject]@{
                steamCmdPath = $script:folder
                steamCredentials = [pscustomobject]@{ usernameBlob = $null; passwordBlob = $null }
            }
        }
        Mock Get-RootConfig {
            [pscustomobject]@{ mods = @(); serverMods = @() }
        }
        Mock Save-RootConfig {}
        Mock Update-GeneratedLaunchFromRootConfig {}
        Mock Remove-WorkshopModFromConfig {}
        Mock Remove-Item {}
        Mock Test-Path { $false }
        Mock Menu {}
        Mock Read-Host {
            $response = $script:readHostResponses[$script:readHostIndex]
            $script:readHostIndex++
            return $response
        }

        Remove_menu

        Assert-MockCalled Test-Path -Times 0 -ParameterFilter { $Path -like '*..\..\Windows*' }
        Assert-MockCalled Remove-Item -Times 0
        Assert-MockCalled Remove-WorkshopModFromConfig -Times 0
        Assert-MockCalled Save-RootConfig -Times 0
    }
}

Describe 'Mod Manager menu navigation' {
    It 'opens client mods on a dedicated screen with a back option' {
        $script:menuTitles = @()
        $script:readHostResponses = @('1', '1', '7')
        $script:readHostIndex = 0

        Mock Show-MenuHeader {
            param($Title)
            $script:menuTitles += $Title
        }

        Mock Show-ConfiguredMods {}
        Mock Pause-BeforeMenu {}
        Mock Menu {}
        Mock Read-Host {
            $response = $script:readHostResponses[$script:readHostIndex]
            $script:readHostIndex++
            return $response
        }

        ModManager_menu

        ($script:menuTitles | Where-Object { $_ -match '^Client mods' }).Count -gt 0 | Should Be $true
        Assert-MockCalled Show-ConfiguredMods -Times 1 -ParameterFilter { $Kind -eq 'mods' }
        Assert-MockCalled Pause-BeforeMenu -Times 0
    }

    It 'renders the updated manage mods menu labels' {
        $script:lastPrompt = $null

        Mock Show-MenuHeader {}
        Mock Menu {}
        Mock Read-Host {
            param([string]$Prompt)

            $script:lastPrompt = $Prompt
            return '7'
        }

        $output = ModManager_menu
        $menuText = $output -join "`n"

        $menuText | Should Match '5\) Move mod between client/server'
        $menuText | Should Match '6\) Sync/update configured mods now'
        $menuText | Should Match '7\) Back to Main Menu'
        $script:lastPrompt | Should Be 'Select an option'
    }
}
