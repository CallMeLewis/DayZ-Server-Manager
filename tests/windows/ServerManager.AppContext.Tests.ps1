$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'selected app context' {
    It 'sets stable app context in script scope' {
        Set-SelectedServerApp 'stable'

        $script:steamApp | Should Be 223350
        $script:appFolder | Should Be '\steamapps\common\DayZServer'
    }

    It 'sets experimental app context in script scope' {
        Set-SelectedServerApp 'exp'

        $script:steamApp | Should Be 1042420
        $script:appFolder | Should Be '\steamapps\common\DayZ Server Exp'
    }
}
