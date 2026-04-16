$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Workshop download helpers' {
    It 'writes one validated download command per workshop id and quits' {
        $scriptPath = Join-Path $TestDrive 'mods.txt'

        New-WorkshopDownloadScript @('1559212036', '1750506510') $scriptPath

        $content = Get-Content -LiteralPath $scriptPath
        ($content -join '|') | Should Be 'workshop_download_item 221100 1559212036 validate|workshop_download_item 221100 1750506510 validate|quit'
    }

    It 'returns false when any requested workshop folder is missing' {
        $workshopRoot = Join-Path $TestDrive '221100'
        New-Item -ItemType Directory -Path (Join-Path $workshopRoot '1559212036') -Force | Out-Null

        Test-WorkshopItemsPresent $workshopRoot @('1559212036', '1750506510') | Should Be $false
    }
}

Describe 'ModsUpdate workshop validation' {
    BeforeEach {
        $script:stateConfigPath = Join-Path $TestDrive 'server-manager.state.json'
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        Save-JsonFile $script:stateConfigPath (New-DefaultStateConfig)
        Clear-SteamCmdSessionCredential

        function robocopy {
            param([string] $Source, [string] $Destination)
            $script:robocopyCalls += [pscustomobject]@{
                Source = $Source
                Destination = $Destination
            }
            $global:LASTEXITCODE = 0
            return 0
        }
    }

    AfterEach {
        Clear-SteamCmdSessionCredential
        Remove-Item function:robocopy -ErrorAction SilentlyContinue
    }

    It 'prompts for a SteamCMD account before mod updates when none is saved' {
        $script:folder = Join-Path $TestDrive 'SteamCMD'
        $script:appFolder = '\steamapps\common\DayZServer'
        $script:tempModList = Join-Path $TestDrive 'mods.txt'
        $script:tempModListServer = Join-Path $TestDrive 'serverMods.txt'
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = $null
        $script:capturedLoginScriptContent = $null
        $global:LASTEXITCODE = 0

        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\workshop\content\221100\1559212036') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\keys') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\1559212036\keys') -Force | Out-Null

        Mock Get-RootConfig {
            [pscustomobject]@{
                mods = @([pscustomobject]@{ workshopId = '1559212036'; name = 'CF'; url = '' })
                serverMods = @()
            }
        }
        Mock Get-ActiveSteamCmdCredential { $null }
        Mock Read-Host { '1' } -ParameterFilter { $Prompt -eq 'Select an option' }
        Mock Prompt-SteamCmdCredential { $script:downloadCredential } -ParameterFilter { $Persist -eq $false }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs = $Arguments
            if ($Arguments[0] -eq '+runscript' -and (Test-Path -LiteralPath $Arguments[1] -ErrorAction SilentlyContinue)) {
                $script:capturedLoginScriptContent = (Get-Content -LiteralPath $Arguments[1] -Raw).Trim()
            }
            return [pscustomobject]@{
                ExitCode = 0
                Output = 'Success'
                StdOut = ''
                StdErr = ''
            }
        }
        Mock Copy-Item {}
        Mock Remove-Item {}

        ModsUpdate | Out-Null

        Assert-MockCalled Prompt-SteamCmdCredential -Times 1 -ParameterFilter { $Persist -eq $false }
        $script:capturedSteamArgs[0] | Should Be '+runscript'
        $script:capturedLoginScriptContent | Should Be 'login dayz-owner secret-pass'
        $opArgs = @($script:capturedSteamArgs[2..($script:capturedSteamArgs.Count - 1)])
        ($opArgs -join ' ') | Should Be "+runscript $script:tempModList"
    }

    It 'uses validated workshop ids for download and copy operations while surfacing invalid config values' {
        $script:folder = Join-Path $TestDrive 'SteamCMD'
        $script:appFolder = '\steamapps\common\DayZServer'
        $script:tempModList = Join-Path $TestDrive 'mods.txt'
        $script:tempModListServer = Join-Path $TestDrive 'serverMods.txt'
        $script:tempLoginScript = Join-Path $TestDrive 'steamcmd-login.tmp'
        $script:robocopyCalls = @()
        $script:copyItemCalls = @()
        $global:LASTEXITCODE = 0

        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\workshop\content\221100\1559212036') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\workshop\content\221100\3703219006') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\keys') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\1559212036\keys') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:folder 'steamapps\common\DayZServer\3703219006\keys') -Force | Out-Null

        Mock Get-RootConfig {
            [pscustomobject]@{
                mods = @(
                    [pscustomobject]@{ workshopId = '1559212036'; name = 'CF'; url = '' }
                    [pscustomobject]@{ workshopId = "..\..\Windows"; name = 'Traversal'; url = '' }
                )
                serverMods = @(
                    [pscustomobject]@{ workshopId = '3703219006'; name = 'Fix'; url = '' }
                    [pscustomobject]@{ workshopId = "1559212036`n+quit"; name = 'Injected'; url = '' }
                )
            }
        }
        $securePassword = ConvertTo-SecureString 'secret-pass' -AsPlainText -Force
        $script:downloadCredential = New-Object System.Management.Automation.PSCredential ('dayz-owner', $securePassword)
        $script:capturedSteamArgs = @()
        Mock Get-ActiveSteamCmdCredential { $script:downloadCredential }
        Mock Get-SavedSteamCmdCredential { $script:downloadCredential }
        Mock Resolve-SteamCmdDownloadCredential { $script:downloadCredential }
        Mock Prompt-SteamCmdCredential { throw 'Prompt-SteamCmdCredential should not be called when a SteamCMD account is already available.' }
        Mock Invoke-SteamCmdCommand {
            param([string[]]$Arguments)
            $script:capturedSteamArgs += ,$Arguments
            [pscustomobject]@{ ExitCode = 0; Output = 'Success'; StdOut = ''; StdErr = '' }
        }
        Mock Copy-Item {
            param([string] $Path, [string] $Destination)
            $script:copyItemCalls += [pscustomobject]@{
                Path = $Path
                Destination = $Destination
            }
        }
        Mock Remove-Item {}

        $script:capturedHostLines = @()
        Mock Write-Host {
            param($Object)
            if ($null -ne $Object) { $script:capturedHostLines += [string]$Object }
        }

        $output = ModsUpdate

        $hostText = $script:capturedHostLines -join "`n"
        $hostText | Should Match ([regex]::Escape('..\..\Windows'))
        $hostText | Should Match 'invalid'

        # All mods (client + server) are downloaded in a single SteamCMD session
        (Get-Content -LiteralPath $script:tempModList) | Should Be @(
            'workshop_download_item 221100 1559212036 validate'
            'workshop_download_item 221100 3703219006 validate'
            'quit'
        )

        @($script:robocopyCalls).Count | Should Be 2
        $script:robocopyCalls[0].Source | Should Be (Join-Path (Join-Path $script:folder 'steamapps\workshop\content\221100') '1559212036')
        $script:robocopyCalls[0].Destination | Should Be (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') '1559212036')
        $script:robocopyCalls[1].Source | Should Be (Join-Path (Join-Path $script:folder 'steamapps\workshop\content\221100') '3703219006')
        $script:robocopyCalls[1].Destination | Should Be (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') '3703219006')

        @($script:copyItemCalls).Count | Should Be 2
        $script:copyItemCalls[0].Path | Should Be (Join-Path (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') '1559212036\keys') '*.bikey')
        $script:copyItemCalls[0].Destination | Should Be (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') 'keys')
        $script:copyItemCalls[1].Path | Should Be (Join-Path (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') '3703219006\keys') '*.bikey')
        $script:copyItemCalls[1].Destination | Should Be (Join-Path (Join-Path $script:folder 'steamapps\common\DayZServer') 'keys')
        $firstCallArgs = @($script:capturedSteamArgs[0]) -join ' '
        $firstCallArgs | Should Match '\+runscript'
        $firstCallArgs | Should Not Match 'secret-pass'
    }
}
