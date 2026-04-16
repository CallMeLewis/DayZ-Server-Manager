$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'JSON config helpers' {
    It 'round trips root config JSON' {
        $path = Join-Path $TestDrive 'server-manager.config.json'
        $config = [pscustomobject]@{
            launchParameters = '-config=serverDZ.cfg'
            mods = @([pscustomobject]@{ name = 'CF'; workshopId = '1559212036'; url = 'https://steamcommunity.com/sharedfiles/filedetails/?id=1559212036' })
            serverMods = @()
        }

        Save-JsonFile $path $config
        $loaded = Get-JsonFile $path

        $loaded.launchParameters | Should Be '-config=serverDZ.cfg'
        $loaded.mods[0].workshopId | Should Be '1559212036'
    }

    It 'throws on invalid JSON instead of replacing it' {
        $path = Join-Path $TestDrive 'bad.json'
        '{"bad":' | Set-Content -LiteralPath $path

        $threw = $false
        try {
            Get-JsonFile $path
        } catch {
            $threw = $true
        }

        $threw | Should Be $true
    }
}
