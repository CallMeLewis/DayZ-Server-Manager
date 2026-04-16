$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'New-DefaultModGroup' {
	It 'creates a group with given name and empty mod lists' {
		$group = New-DefaultModGroup 'Test Group'
		$group.name | Should Be 'Test Group'
		@($group.mods).Count | Should Be 0
		@($group.serverMods).Count | Should Be 0
	}

	It 'creates a group with provided mod id arrays' {
		$group = New-DefaultModGroup 'PvE' @('1559212036','1828439124') @('3705672649')
		@($group.mods).Count | Should Be 2
		$group.mods[0] | Should Be '1559212036'
		@($group.serverMods).Count | Should Be 1
		$group.serverMods[0] | Should Be '3705672649'
	}
}

Describe 'Test-ModGroupNameValid' {
	It 'rejects empty or whitespace names' {
		(Test-ModGroupNameValid '' @()) | Should Be $false
		(Test-ModGroupNameValid '   ' @()) | Should Be $false
	}

	It 'rejects names longer than 64 characters' {
		$long = 'a' * 65
		(Test-ModGroupNameValid $long @()) | Should Be $false
	}

	It 'rejects case-insensitive duplicates in the existing list' {
		$existing = @(
			[pscustomobject]@{ name = 'DeerIsle PvE'; mods = @(); serverMods = @() }
		)
		(Test-ModGroupNameValid 'deerisle pve' $existing) | Should Be $false
	}

	It 'accepts a name that does not collide' {
		$existing = @(
			[pscustomobject]@{ name = 'DeerIsle PvE'; mods = @(); serverMods = @() }
		)
		(Test-ModGroupNameValid 'Namalsk Test' $existing) | Should Be $true
	}

	It 'accepts the current name when renaming in place (IgnoreName parameter)' {
		$existing = @(
			[pscustomobject]@{ name = 'DeerIsle PvE'; mods = @(); serverMods = @() }
		)
		(Test-ModGroupNameValid 'DeerIsle PvE' $existing -IgnoreName 'DeerIsle PvE') | Should Be $true
	}
}

Describe 'Get-ModGroupByName' {
	It 'returns the group when found (case-insensitive)' {
		$groups = @(
			[pscustomobject]@{ name = 'DeerIsle PvE'; mods = @(); serverMods = @() }
			[pscustomobject]@{ name = 'Vanilla+';     mods = @(); serverMods = @() }
		)
		(Get-ModGroupByName $groups 'deerisle pve').name | Should Be 'DeerIsle PvE'
	}

	It 'returns $null when not found' {
		$groups = @(
			[pscustomobject]@{ name = 'DeerIsle PvE'; mods = @(); serverMods = @() }
		)
		Get-ModGroupByName $groups 'Missing' | Should Be $null
	}

	It 'returns $null for empty / null inputs' {
		Get-ModGroupByName @() 'Anything' | Should Be $null
		Get-ModGroupByName $null 'Anything' | Should Be $null
	}
}

Describe 'Resolve-ModGroupAgainstLibrary' {
	It 'splits group ids into resolved and dangling' {
		$library = @{
			mods = @(
				[pscustomobject]@{ workshopId = '1559212036'; name = 'CF';  url = '' }
				[pscustomobject]@{ workshopId = '1828439124'; name = 'VPP'; url = '' }
			)
			serverMods = @(
				[pscustomobject]@{ workshopId = '3705672649'; name = 'Smokey'; url = '' }
			)
		}
		$group = [pscustomobject]@{
			name       = 'Test'
			mods       = @('1559212036', '9999999999')
			serverMods = @('3705672649', '8888888888')
		}

		$result = Resolve-ModGroupAgainstLibrary $library $group

		@($result.ResolvedMods).Count     | Should Be 1
		$result.ResolvedMods[0].name      | Should Be 'CF'
		@($result.DanglingMods).Count     | Should Be 1
		$result.DanglingMods[0]           | Should Be '9999999999'

		@($result.ResolvedServerMods).Count | Should Be 1
		$result.ResolvedServerMods[0].name  | Should Be 'Smokey'
		@($result.DanglingServerMods).Count | Should Be 1
		$result.DanglingServerMods[0]       | Should Be '8888888888'
	}
}

Describe 'Get-GroupsReferencingMod' {
	It 'returns groups whose mods array references the id' {
		$groups = @(
			[pscustomobject]@{ name = 'A'; mods = @('111','222'); serverMods = @() }
			[pscustomobject]@{ name = 'B'; mods = @('333');       serverMods = @() }
			[pscustomobject]@{ name = 'C'; mods = @('222','444'); serverMods = @() }
		)
		$result = Get-GroupsReferencingMod $groups '222' 'mods'
		@($result).Count | Should Be 2
		($result | ForEach-Object { $_.name }) -join ',' | Should Be 'A,C'
	}

	It 'returns groups whose serverMods array references the id' {
		$groups = @(
			[pscustomobject]@{ name = 'A'; mods = @(); serverMods = @('111') }
			[pscustomobject]@{ name = 'B'; mods = @(); serverMods = @('222') }
		)
		$result = Get-GroupsReferencingMod $groups '222' 'serverMods'
		@($result).Count | Should Be 1
		$result[0].name | Should Be 'B'
	}

	It 'returns empty when no group references the id' {
		$groups = @(
			[pscustomobject]@{ name = 'A'; mods = @('111'); serverMods = @() }
		)
		@(Get-GroupsReferencingMod $groups '999' 'mods').Count | Should Be 0
	}
}

Describe 'Sync-LaunchParametersFromActiveGroup' {
	It 'rewrites -mod and -serverMod slots from the active group' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=OLD;" "-serverMod=OLD;" -port=2302 -freezecheck'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @('111','222'); serverMods = @('999') }
			)
		}

		Sync-LaunchParametersFromActiveGroup $config

		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=111;222;" "-serverMod=999;" -port=2302 -freezecheck'
	}

	It 'leaves non-mod portions of launchParameters unchanged' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" "-profiles=D:\logs" -port=2302 -freezecheck -adminlog -dologs'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @('111'); serverMods = @() }
			)
		}

		Sync-LaunchParametersFromActiveGroup $config

		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=111;" "-serverMod=" "-profiles=D:\logs" -port=2302 -freezecheck -adminlog -dologs'
	}

	It 'writes empty mod slots when activeGroup is missing' {
		$config = [pscustomobject]@{
			activeGroup = 'Ghost'
			launchParameters = '-config=serverDZ.cfg "-mod=1;2;" "-serverMod=3;" -port=2302'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @('111'); serverMods = @() }
			)
		}

		Sync-LaunchParametersFromActiveGroup $config

		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=" "-serverMod=" -port=2302'
	}
}

Describe 'Invoke-ModGroupsMigration' {
	It 'creates a Default group from current launch params when modGroups is missing' {
		$config = [pscustomobject]@{
			launchParameters = '-config=serverDZ.cfg "-mod=1559212036;1828439124;" "-serverMod=3705672649;" -port=2302'
			mods       = @(
				[pscustomobject]@{ name = 'A'; workshopId = '1559212036'; url = '' }
				[pscustomobject]@{ name = 'B'; workshopId = '1828439124'; url = '' }
			)
			serverMods = @(
				[pscustomobject]@{ name = 'S'; workshopId = '3705672649'; url = '' }
			)
		}

		$changed = Invoke-ModGroupsMigration $config

		$changed | Should Be $true
		@($config.modGroups).Count | Should Be 1
		$config.modGroups[0].name | Should Be 'Default'
		@($config.modGroups[0].mods).Count | Should Be 2
		$config.modGroups[0].mods[0] | Should Be '1559212036'
		@($config.modGroups[0].serverMods).Count | Should Be 1
		$config.activeGroup | Should Be 'Default'
	}

	It 'is idempotent when modGroups already exists' {
		$config = [pscustomobject]@{
			activeGroup = 'Existing'
			launchParameters = '-config=serverDZ.cfg "-mod=111;" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'Existing'; mods = @('111'); serverMods = @() }
			)
		}

		$changed = Invoke-ModGroupsMigration $config

		$changed | Should Be $false
		@($config.modGroups).Count | Should Be 1
		$config.activeGroup | Should Be 'Existing'
	}

	It 'creates an empty Default group when launch params have no ids' {
		$config = [pscustomobject]@{
			launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
		}

		$changed = Invoke-ModGroupsMigration $config

		$changed | Should Be $true
		$config.modGroups[0].name | Should Be 'Default'
		@($config.modGroups[0].mods).Count | Should Be 0
		@($config.modGroups[0].serverMods).Count | Should Be 0
		$config.activeGroup | Should Be 'Default'
	}
}

Describe 'Mod group missions' {
	It 'captures mission from serverDZ template during migration' {
		$script:tempRoot = Join-Path $env:TEMP "mission-migrate-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
		$script:origRootConfigPath = $rootConfigPath
		$script:rootConfigPath = Join-Path $script:tempRoot 'server-manager.config.json'

		$serverFolder = Join-Path $script:tempRoot 'DayZServer'
		New-Item -ItemType Directory -Path $serverFolder -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $serverFolder 'serverDZ.cfg') -Value 'template="empty.60.deerisle";'

		$old = @{
			launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
			serverFolder = $serverFolder
		}

		$changed = Invoke-ModGroupsMigration $old

		$changed | Should Be $true
		$old.modGroups[0].mission | Should Be 'empty.60.deerisle'

		$script:rootConfigPath = $script:origRootConfigPath
		Remove-Item -Recurse -Force $script:tempRoot -ErrorAction SilentlyContinue
	}
}

Describe 'Mod group mission selection' {
	It 'stores mission on create' {
		$script:serverFolder = Join-Path $env:TEMP "mission-list-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $script:serverFolder -Force | Out-Null
		Mock Get-RootConfig { [pscustomobject]@{ modGroups=@(); activeGroup='Default'; launchParameters=''; mods=@(); serverMods=@() } }
		Mock Get-CurrentServerDirectory { return $script:serverFolder }
		Mock Read-Host { return 'Group A' }
		Mock Select-MissionFromList { return 'empty.60.deerisle' }
		Mock Invoke-ModGroupChecklistEditor { return @{ Saved = $true; Mods=@(); ServerMods=@() } }
		Mock Save-RootConfig {}

		New-ModGroupFromPrompt

		Assert-MockCalled Save-RootConfig -Times 1
		Assert-MockCalled Select-MissionFromList -Times 1 -ParameterFilter { $ServerFolder -eq $script:serverFolder }
	}
}

Describe 'Get-RootConfig mod groups migration' {
	BeforeEach {
		$script:tempRoot = Join-Path $env:TEMP "modgroups-test-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
		$script:origRootConfigPath = $rootConfigPath
		$script:rootConfigPath = Join-Path $script:tempRoot 'server-manager.config.json'
	}

	AfterEach {
		$script:rootConfigPath = $script:origRootConfigPath
		Remove-Item -Recurse -Force $script:tempRoot -ErrorAction SilentlyContinue
	}

	It 'migrates an old-shape config and writes a .bak' {
		$old = @{
			launchParameters = '-config=serverDZ.cfg "-mod=1559212036;1828439124;" "-serverMod=3705672649;" -port=2302'
			mods       = @(@{ name = 'A'; workshopId = '1559212036'; url = '' })
			serverMods = @(@{ name = 'S'; workshopId = '3705672649'; url = '' })
		}
		($old | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $script:rootConfigPath -Encoding UTF8

		$loaded = Get-RootConfig

		$loaded.activeGroup | Should Be 'Default'
		@($loaded.modGroups).Count | Should Be 1
		Test-Path "$script:rootConfigPath.bak" | Should Be $true
	}

	It 'does not re-migrate or re-backup on second load' {
		$config = @{
			activeGroup = 'Default'
			launchParameters = '-config=serverDZ.cfg "-mod=1559212036;" "-serverMod=" -port=2302'
			mods       = @(@{ name = 'A'; workshopId = '1559212036'; url = '' })
			serverMods = @()
			modGroups  = @(@{ name = 'Default'; mods = @('1559212036'); serverMods = @() })
		}
		($config | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $script:rootConfigPath -Encoding UTF8

		$null = Get-RootConfig
		Test-Path "$script:rootConfigPath.bak" | Should Be $false
	}
}

Describe 'Set-ActiveModGroup' {
	It 'sets activeGroup and syncs launch parameters' {
		$config = [pscustomobject]@{
			activeGroup = 'Old'
			launchParameters = '-config=serverDZ.cfg "-mod=OLD;" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'Old'; mods = @('OLD'); serverMods = @() }
				[pscustomobject]@{ name = 'New'; mods = @('111','222'); serverMods = @('999') }
			)
		}

		Set-ActiveModGroup $config 'New'

		$config.activeGroup | Should Be 'New'
		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=111;222;" "-serverMod=999;" -port=2302'
	}

	It 'returns false without changing state when the group does not exist' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=OLD;" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @('OLD'); serverMods = @() }
			)
		}

		(Set-ActiveModGroup $config 'Missing') | Should Be $false
		$config.activeGroup | Should Be 'A'
		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=OLD;" "-serverMod=" -port=2302'
	}
}

Describe 'Set-ActiveModGroup mission sync' {
	It 'updates serverDZ template when active group has a mission' {
		$root = Join-Path $env:TEMP "mission-sync-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $root -Force | Out-Null
		$serverFolder = Join-Path $root 'DayZServer'
		New-Item -ItemType Directory -Path $serverFolder -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $serverFolder 'serverDZ.cfg') -Value 'template="empty.59.deerisle";'

		$config = [pscustomobject]@{
			activeGroup      = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" -port=2302'
			serverFolder     = $serverFolder
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @(); serverMods = @(); mission = 'empty.60.deerisle' }
			)
		}

		Set-ActiveModGroup $config 'A' | Should Be $true

		(Get-Content -LiteralPath (Join-Path $serverFolder 'serverDZ.cfg') -Raw) |
			Should Match 'template="empty.60.deerisle"'
	}
}

Describe 'Sync-ServerConfigMission' {
	It 'uses the current server directory when config lacks serverFolder' {
		$root = Join-Path $env:TEMP "mission-sync-fallback-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $root -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $root 'serverDZ.cfg') -Value 'template="empty.59.deerisle";'

		$config = [pscustomobject]@{}
		Mock Get-CurrentServerDirectory { return $root }

		$result = Sync-ServerConfigMission $config 'empty.60.deerisle'

		$result | Should Be $true
		(Get-Content -LiteralPath (Join-Path $root 'serverDZ.cfg') -Raw) |
			Should Match 'template="empty.60.deerisle"'
	}
}

Describe 'ConvertFrom-ChecklistInput' {
	It 'parses a single number' {
		(ConvertFrom-ChecklistInput '3' 10) -join ',' | Should Be '3'
	}

	It 'parses a comma-separated list' {
		(ConvertFrom-ChecklistInput '1,3,5' 10) -join ',' | Should Be '1,3,5'
	}

	It 'parses a range like 1-4' {
		(ConvertFrom-ChecklistInput '1-4' 10) -join ',' | Should Be '1,2,3,4'
	}

	It 'parses mixed input like "1,3-5,8"' {
		(ConvertFrom-ChecklistInput '1,3-5,8' 10) -join ',' | Should Be '1,3,4,5,8'
	}

	It 'ignores out-of-range numbers' {
		(ConvertFrom-ChecklistInput '1,99' 10) -join ',' | Should Be '1'
	}

	It 'returns empty for non-numeric input' {
		@(ConvertFrom-ChecklistInput 'abc' 10).Count | Should Be 0
	}
}

Describe 'Rename-ModGroup' {
	It 'renames a group and updates activeGroup if needed' {
		$config = [pscustomobject]@{
			activeGroup = 'Old'
			launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" -port=2302'
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'Old'; mods = @(); serverMods = @() }
			)
		}

		(Rename-ModGroup $config 'Old' 'New') | Should Be $true
		$config.modGroups[0].name | Should Be 'New'
		$config.activeGroup | Should Be 'New'
	}

	It 'rejects duplicate new names' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = ''
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @(); serverMods = @() }
				[pscustomobject]@{ name = 'B'; mods = @(); serverMods = @() }
			)
		}

		(Rename-ModGroup $config 'A' 'B') | Should Be $false
		$config.modGroups[0].name | Should Be 'A'
	}
}

Describe 'Remove-ModGroup' {
	It 'removes a non-active group' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = ''
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @(); serverMods = @() }
				[pscustomobject]@{ name = 'B'; mods = @(); serverMods = @() }
			)
		}

		(Remove-ModGroup $config 'B') | Should Be $true
		@($config.modGroups).Count | Should Be 1
		$config.modGroups[0].name | Should Be 'A'
	}

	It 'refuses to remove the active group' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = ''
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @(); serverMods = @() }
				[pscustomobject]@{ name = 'B'; mods = @(); serverMods = @() }
			)
		}

		(Remove-ModGroup $config 'A') | Should Be $false
		@($config.modGroups).Count | Should Be 2
	}

	It 'refuses to remove the last remaining group' {
		$config = [pscustomobject]@{
			activeGroup = 'Only'
			launchParameters = ''
			mods       = @()
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'Only'; mods = @(); serverMods = @() }
			)
		}

		(Remove-ModGroup $config 'Only') | Should Be $false
	}
}

Describe 'Remove-ModFromAllGroups' {
	It 'removes an id from every group that references it' {
		$config = [pscustomobject]@{
			activeGroup = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=111;222;" "-serverMod=" -port=2302'
			mods       = @(
				[pscustomobject]@{ name = 'X'; workshopId = '111'; url = '' }
				[pscustomobject]@{ name = 'Y'; workshopId = '222'; url = '' }
			)
			serverMods = @()
			modGroups  = @(
				[pscustomobject]@{ name = 'A'; mods = @('111','222'); serverMods = @() }
				[pscustomobject]@{ name = 'B'; mods = @('222');       serverMods = @() }
			)
		}

		Remove-ModFromAllGroups $config '222' 'mods'

		@($config.modGroups[0].mods).Count | Should Be 1
		$config.modGroups[0].mods[0] | Should Be '111'
		@($config.modGroups[1].mods).Count | Should Be 0
		$config.launchParameters | Should Be '-config=serverDZ.cfg "-mod=111;" "-serverMod=" -port=2302'
	}
}

Describe 'Show-ModGroupDetail' {
	It 'returns $false when the user cancels group selection' {
		Mock Get-RootConfig {
			return [pscustomobject]@{
				activeGroup      = 'A'
				launchParameters = ''
				mods             = @()
				serverMods       = @()
				modGroups        = @(
					[pscustomobject]@{ name = 'A'; mods = @('111'); serverMods = @() }
				)
			}
		}
		Mock Read-Host { return '0' }

		$result = Show-ModGroupDetail

		$result | Should Be $false
	}
}

Describe 'ModGroupManager menu navigation' {
	It 'does not pause after cancelling view group' {
		$script:readHostResponses = @('6', '7')
		$script:readHostIndex = 0

		Mock Show-MenuHeader {}
		Mock Pause-BeforeMenu {}
		Mock Show-ModGroupDetail { return $false }
		Mock Read-Host {
			$response = $script:readHostResponses[$script:readHostIndex]
			$script:readHostIndex++
			return $response
		}

		ModGroupManager_menu

		Assert-MockCalled Pause-BeforeMenu -Times 0
	}
}

Describe 'Mod groups end-to-end' {
	BeforeEach {
		$script:tempRoot = Join-Path $env:TEMP "modgroups-e2e-$([guid]::NewGuid())"
		New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
		$script:origRootConfigPath = $rootConfigPath
		$script:rootConfigPath = Join-Path $script:tempRoot 'server-manager.config.json'

		$seed = @{
			activeGroup      = 'A'
			launchParameters = '-config=serverDZ.cfg "-mod=111;222;" "-serverMod=999;" "-profiles=D:\logs" -port=2302 -freezecheck -adminlog -dologs'
			mods       = @(
				@{ name = 'X'; workshopId = '111'; url = '' }
				@{ name = 'Y'; workshopId = '222'; url = '' }
			)
			serverMods = @(
				@{ name = 'S'; workshopId = '999'; url = '' }
			)
			modGroups  = @(
				@{ name = 'A'; mods = @('111','222'); serverMods = @('999') }
				@{ name = 'B'; mods = @('111');       serverMods = @()      }
			)
		}
		($seed | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $script:rootConfigPath -Encoding UTF8
	}

	AfterEach {
		$script:rootConfigPath = $script:origRootConfigPath
		Remove-Item -Recurse -Force $script:tempRoot -ErrorAction SilentlyContinue
	}

	It 'switches active group and rewrites launch params' {
		$config = Get-RootConfig
		Set-ActiveModGroup $config 'B' | Should Be $true
		Save-RootConfig $config

		$reloaded = Get-RootConfig
		$reloaded.activeGroup | Should Be 'B'
		($reloaded.launchParameters -match '"-mod=111;"') | Should Be $true
		($reloaded.launchParameters -match '"-serverMod=;?"') | Should Be $true
		($reloaded.launchParameters -match '"-profiles=D:\\logs"') | Should Be $true
	}

	It 'cascade-deletes a library mod referenced by active group' {
		$config = Get-RootConfig
		Remove-ModFromAllGroups $config '222' 'mods'
		Save-RootConfig $config

		$reloaded = Get-RootConfig
		$groupA = Get-ModGroupByName $reloaded.modGroups 'A'
		@($groupA.mods).Count | Should Be 1
		$groupA.mods[0] | Should Be '111'
		($reloaded.launchParameters -match '"-mod=111;"') | Should Be $true
	}
}
