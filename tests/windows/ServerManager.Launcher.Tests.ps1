$launcherPath = Join-Path $PSScriptRoot '..\..\windows\Start_Server_Manager.cmd'

Describe 'Launcher script' {
    It 'does not bypass execution policy' {
        $content = Get-Content -LiteralPath $launcherPath -Raw

        ($content -match 'ExecutionPolicy Bypass') | Should Be $false
    }
}
