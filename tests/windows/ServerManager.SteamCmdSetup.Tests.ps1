$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'SteamCMD setup onboarding' {
    It 'shows first-run guidance with a recommended SteamCMD path and does not request Steam credentials' {
        $script:setupLines = @()

        Mock Show-MenuHeader {}
        Mock SteamCMDFolder { $true }
        Mock SteamCMDExe { $true }
        Mock Prompt-SteamCmdCredential { [pscustomobject]@{ UserName = 'dayz-owner' } }
        Mock Write-Host {
            param($Object)

            if ($null -ne $Object) {
                $script:setupLines += [string]$Object
            }
        }

        Run-InteractiveSteamCmdSetup | Should Be $true

        ($script:setupLines -join "`n") | Should Match 'SteamCMD is required to download and update your DayZ server files'
        ($script:setupLines -join "`n") | Should Match 'Recommended folder: C:\\SteamCMD'
        ($script:setupLines -join "`n") | Should Match 'Press Enter to use the recommended folder, or type a different path'
        ($script:setupLines -join "`n") | Should Match 'A Steam account that owns DayZ is required for downloads and updates'
        Assert-MockCalled Prompt-SteamCmdCredential -Times 0
    }

    It 'uses C:\\SteamCMD as the recommended SteamCMD path' {
        Get-RecommendedSteamCmdPath | Should Be 'C:\SteamCMD'
    }
}

Describe 'SteamCMD argument escaping' {
    It 'returns an empty string when no arguments are supplied' {
        ConvertTo-SteamCmdArgumentString @() | Should Be ''
    }

    It 'leaves simple tokens unquoted' {
        ConvertTo-SteamCmdArgumentString @('+login','dayz-owner','secret-pass','+app_update','223350','validate','+quit') | Should Be '+login dayz-owner secret-pass +app_update 223350 validate +quit'
    }

    It 'quotes arguments containing whitespace' {
        ConvertTo-SteamCmdArgumentString @('+runscript','C:\Temp Path\mods.txt') | Should Be '+runscript "C:\Temp Path\mods.txt"'
    }

    It 'escapes embedded double quotes in quoted arguments' {
        ConvertTo-SteamCmdArgumentString @('+login','user','pa ss"word') | Should Be '+login user "pa ss\"word"'
    }

    It 'represents an empty string argument as a quoted empty token' {
        ConvertTo-SteamCmdArgumentString @('+login','','') | Should Be '+login "" ""'
    }
}
