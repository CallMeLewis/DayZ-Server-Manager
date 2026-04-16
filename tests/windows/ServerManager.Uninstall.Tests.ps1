$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'SteamCMD uninstall arguments' {
    It 'builds uninstall arguments for the selected app id' {
        $args = Get-SteamCmdUninstallArguments 223350

        ($args -join ' ') | Should Be '+app_uninstall 223350 +quit'
    }

    It 'builds the app manifest path for the selected app id' {
        Get-SteamAppManifestPath 'D:\SteamCMD' 1042420 | Should Be 'D:\SteamCMD\steamapps\appmanifest_1042420.acf'
    }

    It 'automatically removes a stale app manifest when the server folder is already gone' {
        $steamRoot = Join-Path $TestDrive 'SteamCMD'
        $manifestDir = Join-Path $steamRoot 'steamapps'
        $manifestPath = Join-Path $manifestDir 'appmanifest_1042420.acf'

        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        Set-Content -Path $manifestPath -Value 'stale'

        $result = Resolve-DayZServerUninstallState (Join-Path $steamRoot 'steamapps\common\DayZ Server Exp') $manifestPath

        $result.ServerFolderExists | Should Be $false
        $result.ManifestExists | Should Be $false
        $result.RemovedStaleManifest | Should Be $true
        Test-Path -LiteralPath $manifestPath | Should Be $false
    }
}
