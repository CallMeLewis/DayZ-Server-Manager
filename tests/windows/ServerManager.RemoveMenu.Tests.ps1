$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Remove menu' {
    It 'does not display a remove steam login option' {
        Mock Show-MenuHeader {}
        Mock Menu {}
        Mock Read-Host { '5' }

        $output = Remove_menu

        ($output -join "`n") | Should Not Match 'Remove Steam login'
    }

    It 'describes the current Documents state in the SteamCMD uninstall flow' {
        $script:prompts = @()
        $script:responses = @('4', 'no', 'no', '5')
        $script:responseIndex = 0

        Mock Show-MenuHeader {}
        Mock Menu {}
        Mock Pause-BeforeMenu {}
        Mock Read-Host {
            param([string]$Prompt)

            $script:prompts += $Prompt
            $response = $script:responses[$script:responseIndex]
            $script:responseIndex += 1
            return $response
        }

        Remove_menu | Out-Null

        (($script:prompts -join "`n") -match [regex]::Escape('Remove the Documents state folder, including saved SteamCMD paths, generated launch mod strings, and tracked server process info? (yes/no)')) | Should Be $true
    }

    It 'renders the updated remove and uninstall menu labels' {
        $script:lastPrompt = $null

        Mock Show-MenuHeader {}
        Mock Menu {}
        Mock Read-Host {
            param([string]$Prompt)

            $script:lastPrompt = $Prompt
            return '5'
        }

        $output = Remove_menu
        $menuText = $output -join "`n"

        $menuText | Should Match '1\) Clear saved SteamCMD path'
        $menuText | Should Match '2\) Remove mod files'
        $menuText | Should Match '3\) Uninstall DayZ server'
        $menuText | Should Match '4\) Uninstall SteamCMD'
        $menuText | Should Match '5\) Back to Main Menu'
        $script:lastPrompt | Should Be 'Select an option'
    }
}
