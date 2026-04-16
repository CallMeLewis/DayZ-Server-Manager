$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'root config migration' {
    It 'migrates launch params and mod lists into root JSON' {
        $root = Join-Path $TestDrive 'root'
        New-Item -ItemType Directory -Path $root | Out-Null
        '-config=serverDZ.cfg' | Set-Content -LiteralPath (Join-Path $root 'launch_params.txt')
        @('#CF - https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036', '1559212036') | Set-Content -LiteralPath (Join-Path $root 'mod_list.txt')
        @('#ServerFix - https://steamcommunity.com/sharedfiles/filedetails/?id=3703219006', '3703219006') | Set-Content -LiteralPath (Join-Path $root 'server_mod_list.txt')

        $jsonPath = Join-Path $root 'server-manager.config.json'
        Initialize-RootConfig $root $jsonPath

        $config = Get-JsonFile $jsonPath
        $config.launchParameters | Should Be '-config=serverDZ.cfg'
        $config.mods[0].name | Should Be 'CF'
        $config.mods[0].workshopId | Should Be '1559212036'
        $config.serverMods[0].workshopId | Should Be '3703219006'
        Test-Path -LiteralPath (Join-Path $root 'mod_list.txt.legacy.bak') | Should Be $true
    }

    It 'creates a default root JSON when no legacy files exist' {
        $root = Join-Path $TestDrive 'fresh-root'
        New-Item -ItemType Directory -Path $root | Out-Null

        $jsonPath = Join-Path $root 'server-manager.config.json'
        Initialize-RootConfig $root $jsonPath

        $config = Get-JsonFile $jsonPath
        $config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=" "-serverMod=" "-profiles=<DayZServerPath>\logs" -port=2302 -freezecheck -adminlog -dologs'
        @($config.mods).Count | Should Be 0
        @($config.serverMods).Count | Should Be 0
    }
}
