$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'DayZ process tracking' {
    It 'writes process metadata instead of a raw PID' {
        $pidFile = Join-Path $TestDrive 'pidServer.txt'
        $process = [pscustomobject]@{
            Id = 1234
            StartTime = [datetime]'2026-04-11T12:00:00Z'
        }

        Add-DayZServerProcessRecord $process 'D:\SteamCMD\steamapps\common\DayZServer\DayZServer_x64.exe' $pidFile

        Get-Content -LiteralPath $pidFile | Should Be '"1234","D:\SteamCMD\steamapps\common\DayZServer\DayZServer_x64.exe","2026-04-11T12:00:00.0000000Z"'
    }

    It 'does not return the current PowerShell process as a tracked DayZ server' {
        $current = Get-Process -Id $PID

        Get-TrackedDayZProcess $current.Id $current.Path $current.StartTime | Should Be $null
    }
}
