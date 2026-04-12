<# 
.SYNOPSIS 
	Script for downloading and managing a DayZ server and its mods.
	
.DESCRIPTION 
	This script downloads and manages SteamCMD, DayZ server files, and DayZ server mod files.
	It can also start the DayZ server with a specified configuration, including launch parameters and the server configuration file.
	
.NOTES 
	File Name  : Server_manager.ps1 
	Author : Bohemia Interactive a.s. - https://feedback.bistudio.com/project/view/2/
	Requires  : PowerShell V4
	Supported OS  : Windows 10, Windows Server 2012 R2 or newer
	
.LINK 
	https://community.bistudio.com/wiki/...

.EXAMPLE 
	Open the main menu:
	 C:\foo> .\Server_manager.ps1
 
.EXAMPLE 
	Update the server:
	 C:\foo> .\Server_manager.ps1 -update server
	 
.EXAMPLE 
	Update both the server and mods, then start the server with saved launch parameters:
	 C:\foo> .\Server_manager.ps1 -u all -s start -lp user
	 
.EXAMPLE 
	Stop tracked running servers:
	 C:\foo> .\Server_manager.ps1 -s stop
	 
.PARAMETER update 
   Update the server and/or mods to the latest version. Can be substituted by -u
   
   Use values:
   server - updates DayZ server files
   mod - updates selected mod files
   all - updates both DayZ server files and mod files
   
.PARAMETER u
   Update the server and/or mods to the latest version. Can be substituted by -update
   
   Use values:
   server - updates DayZ server files
   mod - updates selected mod files
   all - updates both DayZ server files and mod files
   
.PARAMETER server 
   Start or stop the DayZ server. Can be substituted by -s
   Can be combined with -launchParam or -lp.
   
   Use values:
   start - starts the DayZ server
   stop - stops tracked running DayZ servers
   
.PARAMETER s
   Start or stop the DayZ server. Can be substituted by -server
   Can be combined with -launchParam or -lp.
   
   Use values:
   start - starts the DayZ server
   stop - stops tracked running DayZ servers
   
.PARAMETER launchParam
   Choose whether the DayZ server should start with default or saved launch parameters. Can be substituted by -lp
   Must be used with -server or -s.
   The default value is used unless another value is specified.
   
   Use values:
   default - starts the DayZ server with default launch parameters
   user - starts the DayZ server with saved launch parameters
   
.PARAMETER lp
   Choose whether the DayZ server should start with default or saved launch parameters. Can be substituted by -launchParam
   Must be used with -server or -s.
   The default value is used unless another value is specified.
   
   Use values:
   default - starts the DayZ server with default launch parameters
   user - starts the DayZ server with saved launch parameters

.PARAMETER app 
   Select which Steam server application you want to use.
   Can be combined with all other parameters.
   The default value is "stable" if not specified.
   
   Use values:
   stable - stable Steam server app
   exp - experimental Steam server app
  
#> 

#Comand line parameters
param
(
  [string] $u = $null,
  [string] $update = $null,
  [string] $s = $null,
  [string] $server = $null,
  [string] $lp = $null,
  [string] $launchParam = $null,
  [string] $app = $null
)

#Prepare variable for selection in menus
$select = $null

#Prepare variables related to user Documents folder
$userName = $env:USERNAME
$docFolder = 'C:\Users\' + $userName + '\Documents\DayZ_Server'
$steamDoc = $docFolder + '\SteamCmdPath.txt'
$modListPath = $docFolder + '\modListPath.txt'
$serverModListPath = $docFolder + '\serverModListPath.txt'
$modServerPar = $docFolder + '\modServerPar.txt'
$serverModServerPar = $docFolder + '\serverModServerPar.txt'
$userServerParPath = $docFolder + '\userServerParPath.txt'
$pidServer = $docFolder + '\pidServer.txt'
$tempModList = $docFolder + '\tempModList.txt'
$tempModListServer = $docFolder + '\tempModListServer.txt'
$rootConfigPath = Join-Path $PSScriptRoot 'server-manager.config.json'
$stateConfigPath = Join-Path $docFolder 'server-manager.state.json'

#Prepare variables related to SteamCMD folder
$steamApp = $null
$appFolder = $null
$folder = $null
$loadMods = $null
$script:startupBootstrapActive = $false
$script:serverManagerVersion = '1.0.0'
$script:lastServerActionSucceeded = $false


function Test-InteractiveMenuMode {
	return ([string]::IsNullOrEmpty($u) -and [string]::IsNullOrEmpty($update) -and [string]::IsNullOrEmpty($s) -and [string]::IsNullOrEmpty($server))
}

function Clear-MenuScreen {
	if (Test-InteractiveMenuMode)
		{
			Clear-Host
		}
}

function Show-MenuHeader {
	param([string] $Title)

	Clear-MenuScreen
	Write-Host "========================================"
	Write-Host " $Title"
	Write-Host "========================================"
	Write-Host ""
}

function Get-ServerManagementTitle {
	if ($steamApp -eq 1042420)
		{
			return 'Experimental Server Management'
		}

	if ($steamApp -eq 223350)
		{
			return 'Stable Server Management'
		}

	return 'Server Management'
}

function Get-MainMenuTitle {
	return "DayZ Server Manager v$script:serverManagerVersion"
}

function Get-CurrentServerDirectory {
	$state = Get-StateConfig

	if ([string]::IsNullOrWhiteSpace($state.steamCmdPath) -or [string]::IsNullOrWhiteSpace($appFolder))
		{
			return $null
		}

	return [System.IO.Path]::Combine($state.steamCmdPath, $appFolder.TrimStart('\'))
}

function Test-TrackedServerRunning {
	$trackedServers = Get-TrackedServerRecords

	if (!$trackedServers -or ($trackedServers.Count -eq 0))
		{
			return $false
		}

	foreach ($trackedRecord in $trackedServers)
		{
			$process = Get-TrackedDayZProcess ([int] $trackedRecord.id) $trackedRecord.path ([datetime] $trackedRecord.startTime)
			if ($process)
				{
					return $true
				}
		}

	return $false
}

function Show-MainMenuStatus {
	$serverStatus = if (Test-TrackedServerRunning) { 'Running' } else { 'Not running' }
	$serverDirectory = Get-CurrentServerDirectory
	if ([string]::IsNullOrWhiteSpace($serverDirectory))
		{
			$serverDirectory = 'Not configured'
		}

	Write-Host " Session Status"
	Write-Host " ---------------------------------------"
	Write-Host " Server status   : " -NoNewline
	if ($serverStatus -eq 'Running')
		{
			Write-Host $serverStatus -ForegroundColor Green
		} else {
					Write-Host $serverStatus -ForegroundColor Yellow
				}
	Write-Host " Server directory: $serverDirectory"
	Write-Host " ---------------------------------------"
	Write-Host ""
}

function Set-SelectedServerApp {
	param([string] $Mode)

	if ($Mode -eq 'exp')
		{
			$script:steamApp = 1042420
			$script:appFolder = '\steamapps\common\DayZ Server Exp'
			return
		}

	$script:steamApp = 223350
	$script:appFolder = '\steamapps\common\DayZServer'
}

function Pause-BeforeMenu {
	if (Test-InteractiveMenuMode)
		{
			[void](Read-Host -Prompt 'Press Enter to return to menu')
		}
}

function Get-RecommendedSteamCmdPath {
	return 'C:\SteamCMD'
}

function Run-InteractiveSteamCmdSetup {
	$script:startupBootstrapActive = $true

	try
		{
			Show-MenuHeader 'SteamCMD Setup'
			$recommendedPath = Get-RecommendedSteamCmdPath
			Write-Host "SteamCMD is required to download and update your DayZ server files."
			Write-Host "Choose a folder where SteamCMD should be installed."
			Write-Host "Recommended folder: $recommendedPath"
			Write-Host "Press Enter to use the recommended folder, or type a different path."
			Write-Host "A Steam account that owns DayZ is required for downloads and updates."
			Write-Host ""

			if (!(SteamCMDFolder))
				{
					return $false
				}

			if (!(SteamCMDExe))
				{
					return $false
				}

			if (Ensure-SteamCmdCredential)
				{
					return $true
				}

			return $false
		}
	finally
		{
			$script:startupBootstrapActive = $false
		}
}


function Get-StateFileValue {
	param([string] $Path)

	if (!(Test-Path -LiteralPath $Path))
		{
			return $null
		}

	return (Get-Content -LiteralPath $Path -Raw).Trim()
}

function Get-JsonFile {
	param([string] $Path)

	if (!(Test-Path -LiteralPath $Path))
		{
			return $null
		}

	try
		{
			return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
		}
	catch
		{
			throw "Invalid JSON file '$Path': $($_.Exception.Message)"
		}
}

function Save-JsonFile {
	param(
		[string] $Path,
		$Value
	)

	$parent = Split-Path -Parent $Path
	if (!(Test-Path -LiteralPath $parent))
		{
			New-Item -ItemType Directory -Path $parent -Force >$null
		}

	$Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}

function Backup-LegacyConfigFile {
	param([string] $Path)

	if (!(Test-Path -LiteralPath $Path))
		{
			return
		}

	$backup = "$Path.legacy.bak"
	if (!(Test-Path -LiteralPath $backup))
		{
			Rename-Item -LiteralPath $Path -NewName ([System.IO.Path]::GetFileName($backup))
		}
}

function Convert-LegacyModList {
	param([string[]] $Lines)

	$items = @()
	$pendingName = ''
	$pendingUrl = ''

	foreach ($line in $Lines)
		{
			$trimmed = $line.Trim()
			if ([string]::IsNullOrWhiteSpace($trimmed))
				{
					continue
				}

			if ($trimmed -match '^#(.+?)(?:\s+-\s+(https?://\S+))?$')
				{
					$pendingName = $matches[1].Trim()
					if ($matches[2])
						{
							$pendingUrl = $matches[2].Trim()
						} else {
									$pendingUrl = ''
								}
					continue
				}

			if ($trimmed -match '^\d{8,}$')
				{
					$items += [pscustomobject]@{
						name = $pendingName
						workshopId = $trimmed
						url = $pendingUrl
					}
					$pendingName = ''
					$pendingUrl = ''
				}
		}

	return $items
}

function Convert-LegacyPidRecords {
	param([string[]] $Lines)

	$records = @()

	foreach ($line in $Lines)
		{
			$trimmed = $line.Trim()
			if ([string]::IsNullOrWhiteSpace($trimmed))
				{
					continue
				}

			if ($trimmed -match ',')
				{
					$record = $trimmed | ConvertFrom-Csv -Header Id,Path,StartTime
					$records += [pscustomobject]@{
						id = [int] $record.Id
						path = $record.Path
						startTime = $record.StartTime
					}
				} elseif ($trimmed -match '^\d+$') {
							$records += [pscustomobject]@{
								id = [int] $trimmed
								path = ''
								startTime = ''
							}
						}
		}

	return $records
}

function Initialize-RootConfig {
	param(
		[string] $RootPath,
		[string] $ConfigPath
	)

	if (Test-Path -LiteralPath $ConfigPath)
		{
			return
		}

	$launchPath = Join-Path $RootPath 'launch_params.txt'
	$modPath = Join-Path $RootPath 'mod_list.txt'
	$serverModPath = Join-Path $RootPath 'server_mod_list.txt'

	$launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" "-profiles=<DayZServerPath>\logs" -port=2302 -freezecheck -adminlog -dologs'
	if (Test-Path -LiteralPath $launchPath)
		{
			$launchParameters = Get-Content -LiteralPath $launchPath -Raw
			$launchParameters = $launchParameters.Trim()
		}

	$mods = @()
	if (Test-Path -LiteralPath $modPath)
		{
			$mods = Convert-LegacyModList (Get-Content -LiteralPath $modPath)
		}

	$serverMods = @()
	if (Test-Path -LiteralPath $serverModPath)
		{
			$serverMods = Convert-LegacyModList (Get-Content -LiteralPath $serverModPath)
		}

	$config = [pscustomobject]@{
		launchParameters = $launchParameters
		mods = @($mods)
		serverMods = @($serverMods)
	}

	Save-JsonFile $ConfigPath $config

	Backup-LegacyConfigFile $launchPath
	Backup-LegacyConfigFile $modPath
	Backup-LegacyConfigFile $serverModPath
}

function Initialize-StateConfig {
	param(
		[string] $StateRoot,
		[string] $StatePath,
		[string] $ConfigPath
	)

	if (Test-Path -LiteralPath $StatePath)
		{
			return
		}

		$steamCmdPath = Get-StateFileValue (Join-Path $StateRoot 'SteamCmdPath.txt')
		$modLaunch = Get-StateFileValue (Join-Path $StateRoot 'modServerPar.txt')
		$serverModLaunch = Get-StateFileValue (Join-Path $StateRoot 'serverModServerPar.txt')

		$pidPath = Join-Path $StateRoot 'pidServer.txt'
		$trackedServers = @()
		if (Test-Path -LiteralPath $pidPath)
			{
				$trackedServers = Convert-LegacyPidRecords (Get-Content -LiteralPath $pidPath)
			}

		$state = New-DefaultStateConfig
		$state.rootConfigPath = $ConfigPath
		$state.steamCmdPath = $steamCmdPath
		$state.generatedLaunch.mod = if ($null -ne $modLaunch) { $modLaunch } else { '' }
		$state.generatedLaunch.serverMod = if ($null -ne $serverModLaunch) { $serverModLaunch } else { '' }
		$state.trackedServers = @($trackedServers)

	Save-JsonFile $StatePath $state

	Backup-LegacyConfigFile (Join-Path $StateRoot 'SteamCmdPath.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'modListPath.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'serverModListPath.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'userServerParPath.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'modServerPar.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'serverModServerPar.txt')
	Backup-LegacyConfigFile (Join-Path $StateRoot 'pidServer.txt')
}

function Initialize-ConfigFiles {
	Initialize-RootConfig $PSScriptRoot $rootConfigPath
	Initialize-StateConfig $docFolder $stateConfigPath $rootConfigPath
}

function New-DefaultStateConfig {
	return [pscustomobject]@{
		steamCmdPath = $null
		rootConfigPath = $rootConfigPath
		serverSteamAuth = [pscustomobject]@{
			usernameBlob = $null
			passwordBlob = $null
		}
		generatedLaunch = [pscustomobject]@{
			mod = ''
			serverMod = ''
		}
		trackedServers = @()
	}
}

function Get-RootConfig {
	return Get-JsonFile $rootConfigPath
}

function Save-RootConfig {
	param($Config)

	Save-JsonFile $rootConfigPath $Config
}

function Get-StateConfig {
	$state = Get-JsonFile $stateConfigPath
	if (!$state)
		{
			$state = New-DefaultStateConfig
			return $state
		}

	if (($state.PSObject.Properties.Name -contains 'steamCmdLoginMode') -or ($state.PSObject.Properties.Name -contains 'steamCredentials') -or (-not ($state.PSObject.Properties.Name -contains 'serverSteamAuth')))
		{
			$normalizedState = New-DefaultStateConfig
			if ($state.PSObject.Properties.Name -contains 'steamCmdPath')
				{
					$normalizedState.steamCmdPath = $state.steamCmdPath
				}
			if (($state.PSObject.Properties.Name -contains 'rootConfigPath') -and (-not [string]::IsNullOrWhiteSpace([string] $state.rootConfigPath)))
				{
					$normalizedState.rootConfigPath = $state.rootConfigPath
				}
			if (($state.PSObject.Properties.Name -contains 'generatedLaunch') -and $state.generatedLaunch)
				{
					if ($state.generatedLaunch.PSObject.Properties.Name -contains 'mod')
						{
							$normalizedState.generatedLaunch.mod = $state.generatedLaunch.mod
						}
					if ($state.generatedLaunch.PSObject.Properties.Name -contains 'serverMod')
						{
							$normalizedState.generatedLaunch.serverMod = $state.generatedLaunch.serverMod
						}
				}
			if ($state.PSObject.Properties.Name -contains 'trackedServers')
				{
					$normalizedState.trackedServers = @($state.trackedServers)
				}
			if (($state.PSObject.Properties.Name -contains 'serverSteamAuth') -and $state.serverSteamAuth)
				{
					if ($state.serverSteamAuth.PSObject.Properties.Name -contains 'usernameBlob')
						{
							$normalizedState.serverSteamAuth.usernameBlob = $state.serverSteamAuth.usernameBlob
						}
					if ($state.serverSteamAuth.PSObject.Properties.Name -contains 'passwordBlob')
						{
							$normalizedState.serverSteamAuth.passwordBlob = $state.serverSteamAuth.passwordBlob
						}
				}

			Save-StateConfig $normalizedState
			return $normalizedState
		}

	return $state
}

function Save-StateConfig {
	param($State)

	Save-JsonFile $stateConfigPath $State
}

function Protect-StateSecret {
	param(
		[string] $Value,
		[switch] $AsPlainText
	)

	if ([string]::IsNullOrWhiteSpace($Value))
		{
			return $null
		}

	if ($AsPlainText)
		{
			return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
		}

	$secureValue = ConvertTo-SecureString $Value -AsPlainText -Force
	return ConvertFrom-SecureString $secureValue
}

function Unprotect-StateSecret {
	param(
		[string] $Blob,
		[switch] $AsPlainText
	)

	if ([string]::IsNullOrWhiteSpace($Blob))
		{
			return $null
		}

	try
		{
			if ($AsPlainText)
				{
					return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Blob))
				}

			$secureValue = ConvertTo-SecureString $Blob
			return (New-Object System.Management.Automation.PSCredential ('state', $secureValue)).GetNetworkCredential().Password
		}
	catch
		{
			return $null
		}
}

function Save-SteamCmdCredential {
	param([System.Management.Automation.PSCredential] $Credential)

	if (!$Credential)
		{
			return
		}

	$state = Get-StateConfig
	$password = $Credential.GetNetworkCredential().Password
	$state.serverSteamAuth = [pscustomobject]@{
		usernameBlob = Protect-StateSecret $Credential.UserName -AsPlainText
		passwordBlob = Protect-StateSecret $password
	}
	Save-StateConfig $state
}

function Get-SavedSteamCmdCredential {
	$state = Get-StateConfig
	if (!$state -or !($state.PSObject.Properties.Name -contains 'serverSteamAuth') -or !$state.serverSteamAuth)
		{
			return $null
		}

	$username = Unprotect-StateSecret $state.serverSteamAuth.usernameBlob -AsPlainText
	$password = Unprotect-StateSecret $state.serverSteamAuth.passwordBlob

	if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password))
		{
			return $null
		}

	$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
	return New-Object System.Management.Automation.PSCredential ($username, $securePassword)
}

function Prompt-SteamCmdCredential {
	Write-Host "Steam account setup"
	Write-Host "-------------------"
	Write-Host "Use a Steam account that owns DayZ."
	Write-Host "These credentials are stored encrypted for this Windows user."
	Write-Host "If Steam Guard prompts you, approve the sign-in and retry if needed."
	Write-Host ""

	$username = Read-Host -Prompt 'Steam account name'
	if ([string]::IsNullOrWhiteSpace($username))
		{
			Write-Host "No Steam account name was entered."
			Write-Host ""
			return $null
		}

	$securePassword = Read-Host -Prompt 'Steam password' -AsSecureString
	$password = (New-Object System.Management.Automation.PSCredential ('steam', $securePassword)).GetNetworkCredential().Password
	if ([string]::IsNullOrWhiteSpace($password))
		{
			Write-Host "No Steam password was entered."
			Write-Host ""
			return $null
		}

	$credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
	Save-SteamCmdCredential $credential

	Write-Host "Saved encrypted Steam credentials for future downloads."
	Write-Host ""

	return $credential
}

function Ensure-SteamCmdCredential {
	$credential = Get-SavedSteamCmdCredential
	if ($credential)
		{
			return $credential
		}

	return (Prompt-SteamCmdCredential)
}

function Get-ConfiguredWorkshopIds {
	param(
		$Config,
		[string] $Kind
	)

	if (!$Config -or !$Config.$Kind)
		{
			return @()
		}

	$validated = Get-ValidatedWorkshopIdSet @($Config.$Kind)
	return @($validated.Valid)
}

function Get-ValidatedWorkshopIdSet {
	param([object[]] $ConfigItems)

	$valid = @()
	$invalid = @()

	foreach ($item in @($ConfigItems))
		{
			$rawId = $null

			if ($null -eq $item)
				{
					continue
				}

			if ($item.PSObject.Properties.Match('workshopId').Count -gt 0)
				{
					$rawId = $item.workshopId
				} else {
					$rawId = $item
				}

			if ([string]::IsNullOrWhiteSpace([string] $rawId))
				{
					continue
				}

			$trimmed = ([string] $rawId).Trim()

			if ($trimmed -match '^\d{8,}$')
				{
					if ($valid -notcontains $trimmed)
						{
							$valid += $trimmed
						}
				} else {
					$invalid += $rawId
				}
		}

	return [pscustomobject]@{
		Valid = $valid
		Invalid = $invalid
	}
}

function Get-ConfiguredLaunchParameters {
	param($Config)

	if (!$Config)
		{
			return ''
		}

	return $Config.launchParameters
}

function ConvertTo-ModLaunchString {
	param([string[]] $WorkshopIds)

	if (!$WorkshopIds -or ($WorkshopIds.Count -eq 0))
		{
			return ''
		}

	return (($WorkshopIds | ForEach-Object { "$_;" }) -join '')
}

function Set-GeneratedLaunchMods {
	param(
		[string[]] $Mods,
		[string[]] $ServerMods
	)

	$state = Get-StateConfig
	$state.generatedLaunch.mod = ConvertTo-ModLaunchString $Mods
	$state.generatedLaunch.serverMod = ConvertTo-ModLaunchString $ServerMods
	Save-StateConfig $state
}

function Get-GeneratedLaunchMods {
	$state = Get-StateConfig
	return $state.generatedLaunch
}

function Add-TrackedServerRecord {
	param(
		$Process,
		[string] $ServerExe
	)

	$state = Get-StateConfig
	$records = @($state.trackedServers)
	$records += [pscustomobject]@{
		id = $Process.Id
		path = $ServerExe
		startTime = $Process.StartTime.ToUniversalTime().ToString('o')
	}
	$state.trackedServers = @($records)
	Save-StateConfig $state
}

function Get-TrackedServerRecords {
	$state = Get-StateConfig
	return @($state.trackedServers)
}

function Clear-TrackedServerRecords {
	$state = Get-StateConfig
	$state.trackedServers = @()
	Save-StateConfig $state
}

function Get-WorkshopIdFromInput {
	param([string] $InputValue)

	if ([string]::IsNullOrWhiteSpace($InputValue))
		{
			return $null
		}

	$match = [regex]::Match($InputValue, '(?:id=)?(\d{8,})')
	if (!$match.Success)
		{
			return $null
		}

	return $match.Groups[1].Value
}

function New-WorkshopModConfigItem {
	param(
		[string] $WorkshopId,
		[string] $Name,
		[string] $Url
	)

	return [pscustomobject]@{
		name = $Name
		workshopId = $WorkshopId
		url = $Url
	}
}

function Remove-WorkshopModFromConfig {
	param(
		$Config,
		[string] $WorkshopId
	)

	$Config.mods = @(@($Config.mods) | Where-Object { $_.workshopId -ne $WorkshopId })
	$Config.serverMods = @(@($Config.serverMods) | Where-Object { $_.workshopId -ne $WorkshopId })
}

function Add-WorkshopModToConfig {
	param(
		$Config,
		[string] $Kind,
		[string] $WorkshopId,
		[string] $Name,
		[string] $Url
	)

	if (!$Config.$Kind)
		{
			$Config.$Kind = @()
		}

	if (@($Config.$Kind | Where-Object { $_.workshopId -eq $WorkshopId }).Count -gt 0)
		{
			return
		}

	$items = @($Config.$Kind)
	$items += New-WorkshopModConfigItem $WorkshopId $Name $Url
	$Config.$Kind = @($items)
}

function Move-WorkshopModInConfig {
	param(
		$Config,
		[string] $WorkshopId,
		[string] $TargetKind
	)

	$item = @($Config.mods + $Config.serverMods | Where-Object { $_.workshopId -eq $WorkshopId } | Select-Object -First 1)
	if (!$item)
		{
			return
		}

	Remove-WorkshopModFromConfig $Config $WorkshopId
	Add-WorkshopModToConfig $Config $TargetKind $item[0].workshopId $item[0].name $item[0].url
}

function Test-SafeSteamCmdFolderForRemoval {
	param([string] $Path)

	if ([string]::IsNullOrWhiteSpace($Path))
		{
			return $false
		}

	$resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
	if (!$resolved)
		{
			return $false
		}

	$fullPath = [System.IO.Path]::GetFullPath($resolved.ProviderPath).TrimEnd('\')
	$root = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
	if ($fullPath -eq $root)
		{
			return $false
		}

	if ($fullPath -eq $env:USERPROFILE.TrimEnd('\'))
		{
			return $false
		}

	return (Test-Path -LiteralPath (Join-Path $fullPath 'steamcmd.exe') -PathType Leaf)
}

function Test-ExpectedSigner {
	param(
		[string] $Path,
		[string] $ExpectedSubjectPattern
	)

	if (!(Test-Path -LiteralPath $Path -PathType Leaf))
		{
			return $false
		}

	$signature = Get-AuthenticodeSignature -LiteralPath $Path
	return (($signature.Status -eq 'Valid') -and ($signature.SignerCertificate.Subject -match $ExpectedSubjectPattern))
}

function Get-SteamCmdDownloadUrl {
	return 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
}

function ConvertTo-WorkshopIdList {
	param([string[]] $Lines)

	$valid = @()
	$invalid = @()

	foreach ($line in $Lines)
		{
			$trimmed = $line.Trim()

			if ([string]::IsNullOrWhiteSpace($trimmed) -or ($trimmed -match '^#'))
				{
					continue
				}

			if ($trimmed -match '^\d{8,}$')
				{
					$valid += $trimmed
				} else {
							$invalid += $line
						}
		}

	return [pscustomobject]@{
		Valid = $valid
		Invalid = $invalid
	}
}

function New-WorkshopDownloadScript {
	param(
		[string[]] $WorkshopIds,
		[string] $Path
	)

	$parent = Split-Path -Parent $Path
	if (!(Test-Path -LiteralPath $parent))
		{
			New-Item -ItemType Directory -Path $parent -Force >$null
		}

	$commands = @()
	foreach ($id in $WorkshopIds)
		{
			$commands += "workshop_download_item 221100 $id validate"
		}
	$commands += 'quit'
	$commands | Set-Content -LiteralPath $Path -Force
}

function Test-WorkshopItemsPresent {
	param(
		[string] $WorkshopFolder,
		[string[]] $WorkshopIds
	)

	foreach ($id in $WorkshopIds)
		{
			if (!(Test-Path -LiteralPath (Join-Path $WorkshopFolder $id) -PathType Container))
				{
					return $false
				}
		}

	return $true
}

function Add-DayZServerProcessRecord {
	param(
		$Process,
		[string] $ServerExe,
		[string] $Path
	)

	$parent = Split-Path -Parent $Path
	if (!(Test-Path -LiteralPath $parent))
		{
			New-Item -ItemType Directory -Path $parent -Force >$null
		}

	$record = [pscustomobject]@{
		Id = $Process.Id
		Path = $ServerExe
		StartTime = $Process.StartTime.ToUniversalTime().ToString('o')
	}

	$record | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content "$Path"
}

function Get-TrackedDayZProcess {
	param(
		[int] $Id,
		[string] $ExpectedPath,
		[datetime] $ExpectedStartTime
	)

	$process = Get-Process -Id $Id -ErrorAction SilentlyContinue
	if (!$process)
		{
			return $null
		}

	if ($process.ProcessName -ne 'DayZServer_x64')
		{
			return $null
		}

	if ($process.Path -and ($process.Path -ne $ExpectedPath))
		{
			return $null
		}

	if ($process.StartTime.ToUniversalTime().ToString('o') -ne $ExpectedStartTime.ToUniversalTime().ToString('o'))
		{
			return $null
		}

	return $process
}

function Update-GeneratedLaunchFromRootConfig {
	param($Config)

	$mods = Get-ConfiguredWorkshopIds $Config 'mods'
	$serverMods = Get-ConfiguredWorkshopIds $Config 'serverMods'
	Set-GeneratedLaunchMods $mods $serverMods
}

function Show-ConfiguredMods {
	param([string] $Kind)

	$config = Get-RootConfig
	$items = @($config.$Kind)
	$count = 1

	if ($items.Count -eq 0)
		{
			echo "No mods configured."
			echo "`n"
			return
		}

	foreach ($item in $items)
		{
			$name = $item.name
			if ([string]::IsNullOrWhiteSpace($name))
				{
					$name = '(no name)'
				}

			echo "$count) $name - $($item.workshopId)"
			if (![string]::IsNullOrWhiteSpace($item.url))
				{
					echo "   $($item.url)"
				}
			$count++
	}
	echo "`n"
}

function Show-ConfiguredModsMenu {
	param(
		[string] $Kind,
		[string] $Title
	)

	while ($true)
		{
			Show-MenuHeader $Title
			Show-ConfiguredMods $Kind
			echo "1) Back"
			echo "`n"

			$selection = Read-Host -Prompt 'Select an option'

			if ($selection -eq '1')
				{
					return
				}

			echo "`n"
			echo "Select a number from the list (1)."
			echo "`n"
			Pause-BeforeMenu
		}
}

function Add-ConfiguredModFromPrompt {
	param([string] $Kind)

	$config = Get-RootConfig
	$rawInput = Read-Host -Prompt 'Paste a Steam Workshop URL or mod ID'
	$workshopId = Get-WorkshopIdFromInput $rawInput

	if (!$workshopId)
		{
			echo "No valid Workshop ID was found."
			echo "`n"
			return
		}

	if ((@($config.mods) + @($config.serverMods) | Where-Object { $_.workshopId -eq $workshopId }).Count -gt 0)
		{
			echo "Workshop ID $workshopId is already configured. Use Move mod if it belongs in the other list."
			echo "`n"
			return
		}

	$name = Read-Host -Prompt 'Enter a name for this mod'
	$url = ''
	if ($rawInput -match '^https?://')
		{
			$url = $rawInput
		} else {
					$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId"
				}

	Add-WorkshopModToConfig $config $Kind $workshopId $name $url
	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	echo "Added Workshop ID $workshopId."
	echo "`n"
}

function Remove-ConfiguredModFromPrompt {
	$config = Get-RootConfig
	$rawInput = Read-Host -Prompt 'Paste a Steam Workshop URL or mod ID to remove'
	$workshopId = Get-WorkshopIdFromInput $rawInput

	if (!$workshopId)
		{
			echo "No valid Workshop ID was found."
			echo "`n"
			return
		}

	Remove-WorkshopModFromConfig $config $workshopId
	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	echo "Removed Workshop ID $workshopId from the configured mod lists."
	echo "`n"
}

function Move-ConfiguredModFromPrompt {
	$config = Get-RootConfig
	$rawInput = Read-Host -Prompt 'Paste a Steam Workshop URL or mod ID to move'
	$workshopId = Get-WorkshopIdFromInput $rawInput

	if (!$workshopId)
		{
			echo "No valid Workshop ID was found."
			echo "`n"
			return
		}

	echo "Move to:"
	echo "1) Client mods (-mod)"
	echo "2) Server mods (-serverMod)"
	echo "`n"
	$target = Read-Host -Prompt 'Select an option'

	if ($target -eq '1')
		{
			Move-WorkshopModInConfig $config $workshopId 'mods'
		} elseif ($target -eq '2') {
					Move-WorkshopModInConfig $config $workshopId 'serverMods'
				} else {
							echo "Select a number from the list (1-2)."
							echo "`n"
							return
						}

	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	echo "Moved Workshop ID $workshopId."
	echo "`n"
}

function ModManager_menu {
	Show-MenuHeader 'Manage Mods'

	echo "1) List client mods"
	echo "2) List server mods"
	echo "3) Add client mod"
	echo "4) Add server mod"
	echo "5) Move mod between client and server lists"
	echo "6) Remove mod from configuration"
	echo "7) Back to Main Menu"
	echo "`n"

	$select = Read-Host -Prompt 'Select an option'

	switch ($select)
		{
			1 {
				Show-ConfiguredModsMenu 'mods' 'Client mods'
				ModManager_menu
				Break
			}
			2 {
				Show-ConfiguredModsMenu 'serverMods' 'Server mods'
				ModManager_menu
				Break
			}
			3 {
				Add-ConfiguredModFromPrompt 'mods'
				Pause-BeforeMenu
				ModManager_menu
				Break
			}
			4 {
				Add-ConfiguredModFromPrompt 'serverMods'
				Pause-BeforeMenu
				ModManager_menu
				Break
			}
			5 {
				Move-ConfiguredModFromPrompt
				Pause-BeforeMenu
				ModManager_menu
				Break
			}
			6 {
				Remove-ConfiguredModFromPrompt
				Pause-BeforeMenu
				ModManager_menu
				Break
			}
			7 {
				Menu
				Break
			}
			Default {
				echo "`n"
				echo "Select a number from the list (1-7)."
				echo "`n"
				Pause-BeforeMenu
				ModManager_menu
			}
		}
}


#Main menu
function Menu {
	Show-MenuHeader (Get-ServerManagementTitle)
	Show-MainMenuStatus

	echo "1) Update server"
	echo "2) Update mods"
	echo "3) Start server"
	echo "4) Stop server"
	echo "5) Remove / Uninstall"
	echo "6) Manage mods"
	echo "7) Exit"
	echo "`n"

	$select = Read-Host -Prompt 'Select an option'
	
    switch ($select)
        {
            #Call server update and related functions
            1 {
                echo "`n"
			    echo "Update server selected."
			    echo "`n"
			
			    [void](SteamCMDFolder)
			    [void](SteamCMDExe)
			    SteamLogin
			
				Pause-BeforeMenu
			    Menu

                Break
            } 

            #Call mods update and related functions
            2 {
                echo "`n"
				echo "Update mods selected."
				echo "`n"
						
				[void](SteamCMDFolder)
				[void](SteamCMDExe)
				SteamLogin
						
				Pause-BeforeMenu
				Menu

                Break
            }

            #Start DayZ server
            3 {
                echo "`n"
				echo "Start server selected."
				echo "`n"
								
			    [void](SteamCMDFolder)
								
				$select = $null
				$script:lastServerActionSucceeded = $false
				Server_menu

				if ($script:lastServerActionSucceeded)
					{
						Menu
						Break
					}

				Pause-BeforeMenu
				Menu

                Break
            }

            #Stop running server
            4 {
                echo "`n"
				echo "Stop server selected."
				echo "`n"
				$script:lastServerActionSucceeded = $false
				ServerStop

				if ($script:lastServerActionSucceeded)
					{
						Menu
						Break
					}

				Pause-BeforeMenu
				Menu

                Break
            }

            #Purge saved login/path info
            5 {
                echo "`n"
				echo "Remove / Uninstall selected."
				echo "`n"
												
				Remove_menu
                
                Break
            }

            #Manage mods
            6 {
                echo "`n"
				echo "Manage mods selected."
				echo "`n"
												
				ModManager_menu
                
                Break
            }

            #Close script
            7 {
                echo "`n"
				echo "Exit selected."
				echo "`n"
														
				exit 0

                Break
            }

            #Force user to select one of provided options
            Default {
                
                echo "`n"
				echo "Select a number from the list (1-7)."
				echo "`n"
									
				Pause-BeforeMenu
				Menu
        }
}
}


#SteamCMD folder
function SteamCMDFolder {
	$state = Get-StateConfig

	#Check for saved SteamCMD folder in JSON state
	if ([string]::IsNullOrWhiteSpace($state.steamCmdPath))
		{
			$recommendedFolder = Get-RecommendedSteamCmdPath

			#Prompt user to insert path to SteamCMD folder
			$script:folder = Read-Host -Prompt "Enter the SteamCMD folder path, or press Enter to use $recommendedFolder"
			$folder = $script:folder

			#Check if path was really inserted
			if ([string]::IsNullOrWhiteSpace($folder))
				{
					$script:folder = $recommendedFolder
					$folder = $script:folder
					echo "`n"
					echo "Using the recommended SteamCMD folder: $folder"
					echo "`n"
				}
			
			echo "`n"
			echo "SteamCMD folder: $folder"
			echo "`n"
			
			#Create SteamCMD folder if it doesn't exist
			if (!(Test-Path "$folder"))
				{
					echo "Created the SteamCMD folder."
					echo "`n"
					
					mkdir "$folder" >$null
				}

			#Prompt user to save path to SteamCMD folder for future use
			$saveFolder = Read-Host -Prompt 'Save this path for future use? (yes/no)'

			if ( ($saveFolder -eq "yes") -or ($saveFolder -eq "y")) 
				{ 	
					#Save path to SteamCMD folder in JSON state
					$state.steamCmdPath = $folder
					Save-StateConfig $state
					
					echo "`n"
					echo "Saved the path to $stateConfigPath."
					echo "`n"
				}
		} else {
					#Use saved path to SteamCMD folder
					$script:folder = $state.steamCmdPath
					$folder = $script:folder
					
					echo "SteamCMD folder: $folder"
					echo "`n"
					
					#Create SteamCMD folder if it doesn't exist
					if (!(Test-Path "$folder"))
						{
							echo "Created the SteamCMD folder."
							echo "`n"
							
							mkdir "$folder" >$null
						}
				}

	return $true
}


#SteamCMD exe
function SteamCMDExe {
	#Check if SteamCMD.exe exist
			if (!(Test-Path "$folder\steamcmd.exe")) 
		{
			echo "`n"
			#Prompt user to download and install SteamCMD
			$steamInst = Read-Host -Prompt "'$folder\steamcmd.exe' was not found. Download and install SteamCMD to this folder? (yes/no)"
			echo "`n"
			
			if ( ($steamInst -eq "yes") -or ($steamInst -eq "y")) 
				{ 
					echo "Downloading and installing SteamCMD..."
					echo "`n"

                    #Get Powershell version for compatibility check
					$psVer = $PSVersionTable.PSVersion.Major

                    if ($psVer -gt 3) 
	                    { 

				            echo "Using PowerShell version $psVer"
							echo "`n"

                            #Download SteamCMD
                            $downloadURL = Get-SteamCmdDownloadUrl
                            $destPath = "$folder\steamcmd.zip"

                            (New-Object System.Net.WebClient).DownloadFile($downloadURL, $destPath)

                            #Unzip SteamCMD
                            $shell = New-Object -ComObject Shell.Application
                            $zipFile = $shell.NameSpace($destPath)
                            $unzipPath = $shell.NameSpace("$folder")

                            $copyFlags = 0x00
                            $copyFlags += 0x04 # Hide progress dialogs
                            $copyFlags += 0x10 # Overwrite existing files

                            $unzipPath.CopyHere($zipFile.Items(), $copyFlags)

							$steamCmdExe = Join-Path $folder 'steamcmd.exe'
							if (!(Test-ExpectedSigner $steamCmdExe 'Valve Corp\.'))
								{
									echo "The downloaded steamcmd.exe file does not have a valid Valve signature. Aborting."
									Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
									if ($script:startupBootstrapActive)
										{
											return $false
										}
									pause
									Menu
								}
						
						#If Powershell version is under 4
			            } else { 
						            echo "`n"
									echo "PowerShell version $psVer is not supported."
									echo "`n"
					           }
					
					#Update SteamCMD to latest version
					Start-Process -FilePath "$folder\steamcmd.exe" -ArgumentList ('+quit') -Wait -NoNewWindow
					
					sleep -Seconds 1 
					
					if (Test-Path "$folder\steamcmd.exe") 
						{
							#Remove SteamCMD zip file after successful installation
							Remove-Item -Path "$folder\steamcmd.zip" -Force
							
							echo "`n"
							echo "SteamCMD was successfully installed."
							echo "`n"
							
						} else {
									#Throw error if SteamCMD doesn't exist after installation
									echo "$folder\steamcmd.exe was not found."
									echo "`n"
									
									if ($script:startupBootstrapActive)
										{
											return $false
										}
									pause
									
									Menu
								}
				} else {
							#Throw error if SteamCMD doesn't exist and user chose not to install
							echo "$folder\steamcmd.exe was not found."
							echo "`n"
							
							if ($script:startupBootstrapActive)
								{
									return $false
								}
							pause
							
							Menu
						}			
		}

	return $true
}

function Get-SteamCmdLoginArguments {
	$credential = Ensure-SteamCmdCredential
	if (!$credential)
		{
			throw [System.InvalidOperationException] 'Steam account credentials are required to download and update DayZ server files and mods.'
		}

	return @('+login', $credential.UserName, $credential.GetNetworkCredential().Password)
}

function Get-SteamCmdUninstallArguments {
	param([int] $AppId)

	return @('+app_uninstall', $AppId, '+quit')
}

function Get-SteamAppManifestPath {
	param(
		[string] $SteamCmdRoot,
		[int] $AppId
	)

	return (Join-Path (Join-Path $SteamCmdRoot 'steamapps') "appmanifest_$AppId.acf")
}

function Resolve-DayZServerUninstallState {
	param(
		[string] $ServerFolder,
		[string] $AppManifestPath
	)

	$result = [pscustomobject]@{
		ServerFolderExists   = (Test-Path -LiteralPath $ServerFolder)
		ManifestExists       = (Test-Path -LiteralPath $AppManifestPath)
		RemovedStaleManifest = $false
	}

	if ((-not $result.ServerFolderExists) -and $result.ManifestExists)
		{
			Remove-Item -LiteralPath $AppManifestPath -Force
			$result.ManifestExists = (Test-Path -LiteralPath $AppManifestPath)
			$result.RemovedStaleManifest = (-not $result.ManifestExists)
		}

	return $result
}

function Invoke-SteamCmdCommand {
	param([string[]] $Arguments)

	$output = & "$folder\steamcmd.exe" @Arguments 2>&1
	$exitCode = $LASTEXITCODE
	$lines = @()

	foreach ($entry in @($output))
		{
			$line = [string] $entry
			$lines += $line
			echo $line
		}

	return [pscustomobject]@{
		ExitCode = $exitCode
		Output   = ($lines -join [Environment]::NewLine)
		StdOut   = ($lines -join [Environment]::NewLine)
		StdErr   = ''
	}
}

function Write-SteamCmdFailureGuidance {
	param(
		[int] $ExitCode,
		[string] $Output,
		[string] $Operation
	)

	if (($ExitCode -eq 5) -or ($Output -match 'Invalid Password|Login Failure|Steam Guard|two-factor|Two-factor'))
		{
			echo "SteamCMD sign-in failed for the saved Steam account."
			echo "If Steam Guard is enabled, approve the sign-in and retry."
			echo "Re-enter your Steam credentials if your password has changed."
			echo "`n"
			return
		}

	if ($Output -match 'No subscription')
		{
			echo "Steam denied access to DayZ Server for the saved account."
			echo "Check that this Steam account owns DayZ and approve any Steam Guard request, then retry."
			echo "`n"
		}
}

#Steam login
function SteamLogin {
	#Server update selected
	if ($select -eq '1') 
		{ 
			ServerUpdate
		}
		
	#Mods update selected
	if ($select -eq '2') 
		{ 
			ModsUpdate
		}
}
				
#Update DayZ server data
function ServerUpdate {
	
	echo "Updating the DayZ server..."
	echo "`n"

	#Login to SteamCMD and update DayZ server app
	$loginArgs = Get-SteamCmdLoginArguments
	$proc = Invoke-SteamCmdCommand ($loginArgs + @('+app_update', $steamApp, 'validate', '+quit'))
	if ($proc.ExitCode -ne 0)
		{
			Write-SteamCmdFailureGuidance $proc.ExitCode $proc.Output 'server update'
			echo "SteamCMD server update failed with exit code $($proc.ExitCode)."
			return
		}

	sleep -Seconds 1 
	
	$script:steamUs = $null
	$script:steamPw = $null

	echo "`n"
	echo "DayZ server was updated to the latest version."
	echo "`n"
	
}

#Update mods
function ModsUpdate {
	
	#Path to DayZ server folder
	$serverFolder = $folder + $appFolder 
	
	#Check if DayZ server folder exists
	if (!(Test-Path "$serverFolder"))
		{
			echo "The DayZ server folder was not found. Run Update server before Update mods."
			echo "`n"
			
	} else {
	
					#Load mods from JSON root config
					$rootConfig = Get-RootConfig
					$modsResult = Get-ValidatedWorkshopIdSet @($rootConfig.mods)
					$serverModsResult = Get-ValidatedWorkshopIdSet @($rootConfig.serverMods)
					$mods = @($modsResult.Valid)
					$serverMods = @($serverModsResult.Valid)
					$wrongId = @($modsResult.Invalid)
					$wrongServerId = @($serverModsResult.Invalid)

					if ((!$mods) -and (!$serverMods))
						{
							echo "Both mod lists are empty. Add at least one mod in Manage Mods."
							echo "`n"
							Menu
						}
					
					#List wrong format ids
					echo "The following mod IDs are invalid:"
					echo "`n"
					echo "Client mods:"
					echo $wrongId
					echo "`n"
					echo "Server mods:"
					echo $wrongServerId
					echo "`n"

					#List correct format ids
					echo "The following mod IDs will be updated:"
					echo "`n"
					echo "Client mods:"
					echo $mods
					echo "`n"
					echo "Server mods:"
					echo $serverMods
					echo "`n"

					#Path to SteamCMD DayZ Workshop content folder
					$workshopFolder = $folder + '\steamapps\workshop\content\221100' 
					
					#Download mods from the list
					if ($rootConfig.mods -and ($mods.Count -eq 0))
						{
							echo "Mod list contains no valid Workshop IDs. Skipping mod download."
							echo "`n"
						}
					
					if ($mods.Count -gt 0)
						{
							New-WorkshopDownloadScript $mods "$tempModList"

							echo "Starting download for $($mods.Count) mods..."
							echo "`n"

							#Login to SteamCMD and download/update selected mods
							$loginArgs = Get-SteamCmdLoginArguments
							$proc = Invoke-SteamCmdCommand ($loginArgs + @('+runscript', "$tempModList"))
							if ($proc.ExitCode -ne 0)
								{
									Write-SteamCmdFailureGuidance $proc.ExitCode $proc.Output 'mod update'
									echo "SteamCMD workshop update failed with exit code $($proc.ExitCode)."
									Remove-Item -Path "$tempModList" -Force -ErrorAction SilentlyContinue
									return
								}
									
							sleep -Seconds 1

							Remove-Item -Path "$tempModList" -Force -ErrorAction SilentlyContinue

						}
                         					
					#Copy downloaded mods to server folder if all previous downloads were succesfull
					if ($mods.Count -gt 0)
						{ 
							if (!(Test-WorkshopItemsPresent $workshopFolder $mods))
								{
									echo "One or more requested mod folders are missing after SteamCMD update. Aborting copy."
									return
								}
							
							#Copy mods from workshop folder to DayZ server folder
                            echo "`n"
							echo "Copying mods to the DayZ server folder..."
							echo "`n"
							
							foreach ($mod in $mods)
								{
									robocopy (Join-Path $workshopFolder $mod) (Join-Path $serverFolder $mod) /E /is /it /np /njs /njh /ns /nc /ndl /nfl
									if ($LASTEXITCODE -gt 7)
										{
											echo "Copy failed for mod $mod with robocopy exit code $LASTEXITCODE."
											return
										}
								}
							
							#Copy mod bikeys from mod keys folders to server keys folder
							foreach ($mod in $mods)
								{
									$keyPath = Join-Path (Join-Path $serverFolder $mod) 'keys'
									if (Test-Path -LiteralPath $keyPath -PathType Container)
										{
											Copy-Item -Path (Join-Path $keyPath '*.bikey') -Destination (Join-Path $serverFolder 'keys') -ErrorAction SilentlyContinue
										}
								}
							
							echo "Copied the selected mods to the DayZ server folder."
							echo "`n"
							
						} 

					#Download Server mods from the list
					if ($rootConfig.serverMods -and ($serverMods.Count -eq 0))
						{
							echo "Server mod list contains no valid Workshop IDs. Skipping server mod download."
							echo "`n"
						}

					if ($serverMods.Count -gt 0)
						{
							New-WorkshopDownloadScript $serverMods "$tempModListServer"

							echo "Starting download for $($serverMods.Count) server mods..."
							echo "`n"

							#Login to SteamCMD and download/update selected server mods
							$loginArgs = Get-SteamCmdLoginArguments
							$proc = Invoke-SteamCmdCommand ($loginArgs + @('+runscript', "$tempModListServer"))
							if ($proc.ExitCode -ne 0)
								{
									Write-SteamCmdFailureGuidance $proc.ExitCode $proc.Output 'server mod update'
									echo "SteamCMD workshop update failed with exit code $($proc.ExitCode)."
									Remove-Item -Path "$tempModListServer" -Force -ErrorAction SilentlyContinue
									return
								}
									
							sleep -Seconds 1 

							Remove-Item -Path "$tempModListServer" -Force -ErrorAction SilentlyContinue

						}
						
					#Copy downloaded server mods to server folder if all previous downloads were succesfull
					if ($serverMods.Count -gt 0)
						{ 
							if (!(Test-WorkshopItemsPresent $workshopFolder $serverMods))
								{
									echo "One or more requested server mod folders are missing after SteamCMD update. Aborting copy."
									return
								}
							
							#Copy server mods from workshop folder to DayZ server folder
                            echo "`n"
							echo "Copying server mods to the DayZ server folder..."
							echo "`n"
							
							foreach ($serverMod in $serverMods)
								{
									robocopy (Join-Path $workshopFolder $serverMod) (Join-Path $serverFolder $serverMod) /E /is /it /np /njs /njh /ns /nc /ndl /nfl
									if ($LASTEXITCODE -gt 7)
										{
											echo "Copy failed for server mod $serverMod with robocopy exit code $LASTEXITCODE."
											return
										}
								}
							
							#Copy mod bikeys from mod keys folders to server keys folder
							foreach ($serverMod in $serverMods)
								{
									$keyPath = Join-Path (Join-Path $serverFolder $serverMod) 'keys'
									if (Test-Path -LiteralPath $keyPath -PathType Container)
										{
											Copy-Item -Path (Join-Path $keyPath '*.bikey') -Destination (Join-Path $serverFolder 'keys') -ErrorAction SilentlyContinue
										}
								}
							
							echo "Copied the selected server mods to the DayZ server folder."
							echo "`n"
							
						}

					Set-GeneratedLaunchMods $mods $serverMods

                    $script:steamUs = $null
					$script:steamPw = $null 

				}
}

#Run DayZ server with mods
function Server_menu {
	
	#Path to server folder
	$serverFolder = $folder + $appFolder
	
	#Get generated mod launch strings from JSON state
	$generatedLaunch = Get-GeneratedLaunchMods
	$modsServer = $generatedLaunch.mod
	$serverModsServer = $generatedLaunch.serverMod
		
	#Check if DayZ server exe exists
	if (!(Test-Path "$serverFolder"))
		{
			echo "The DayZ server folder was not found in $serverFolder. Run Update server to download or repair the server data."
			echo "`n"
			$script:lastServerActionSucceeded = $false
			return
		} else {
	
                    switch ($select)
                        {
                            #Start server menu
                            $null {
										Show-MenuHeader 'Start Server'

							            echo "1) Use saved launch parameters"
							            echo "2) Use default launch parameters"
							            echo "3) Back"
							            echo "`n"

							            $select = Read-Host -Prompt 'Select an option'

                                        Server_menu

                                        return
                                }
                            
                            #Use user provided server parameters
                            1 {
                                    echo "`n"
							        echo "Saved launch parameters selected."
							        echo "`n"
							
							        $serverPar = Get-ConfiguredLaunchParameters (Get-RootConfig)
								
								        #Check if user server launch parameters were properly loaded
								        if (!$serverPar)
								        {
									        echo "Saved launch parameters are empty or could not be loaded."
									        echo "`n"
									
									        #Return to Main menu if it wasn't started from CMD			
								        if (($s -eq "") -and ($server -eq "")) 
										        { 
											        $select = $null
													$script:lastServerActionSucceeded = $false

											        return
										        }
										
									        exit 0
								        }
								
								        echo "Starting the DayZ server with saved launch parameters..."
								        echo "`n"
									
								        #Run server
										$serverExe = Join-Path $serverFolder 'DayZServer_x64.exe'
								        $procServer = Start-Process -FilePath "$serverExe" -PassThru -ArgumentList "`"-bepath=$serverFolder\battleye`" $serverPar"
										
								        #Save server process metadata for future use
										Add-TrackedServerRecord $procServer $serverExe
										
								        sleep -Seconds 5	
										
								        echo "The DayZ server is now running."
								        echo "`n"

                                        $script:lastServerActionSucceeded = $true
										return
                                }
                            
                            #Use default server parameters
                            2 {
                                    echo "`n"
									echo "Default launch parameters selected."
									echo "`n"
										
									echo "Starting the DayZ server with default launch parameters..."
									echo "`n"

									#Run server
									$serverExe = Join-Path $serverFolder 'DayZServer_x64.exe'
									$procServer = Start-Process -FilePath "$serverExe" -PassThru -ArgumentList "`"-config=$serverFolder\serverDZ.cfg`" `"-mod=$modsServer`" `"-serverMod=$serverModsServer`" `"-bepath=$serverFolder\battleye`" `"-profiles=$serverFolder\logs`" -port=2302 -freezecheck -adminlog -dologs"
										
									#Save server process metadata for future use
									Add-TrackedServerRecord $procServer $serverExe
										
									sleep -Seconds 5	
										
									echo "The DayZ server is now running."
									echo "`n"

                                    $script:lastServerActionSucceeded = $true
									return
                                }

                            #Return to previous menu
                            3 {
                                    $script:lastServerActionSucceeded = $false
									return
                                }
                            
                            #Force user to select one of provided options
                            Default {
                                        echo "`n"
										echo "Select a number from the list (1-3)."
										echo "`n"
															
										$select = $null
															
										Pause-BeforeMenu
										Server_menu
										return
                                }
                        }
				}               
	$script:lastServerActionSucceeded = $false
}

#Stop running DayZ server
function ServerStop {

	$trackedServers = Get-TrackedServerRecords
	$stoppedCount = 0

	#Check if process list is not empty
	if (!$trackedServers -or ($trackedServers.Count -eq 0))
		{
			echo "No tracked DayZ server is running, or it was not started by this script."
			echo "`n"
			$script:lastServerActionSucceeded = $false
			return
		} else {
					#Try every process record in list
					foreach ($trackedRecord in $trackedServers)
						{
							$displayPid = $trackedRecord.id
							$killServer = Get-TrackedDayZProcess ([int] $trackedRecord.id) $trackedRecord.path ([datetime] $trackedRecord.startTime)
							
							#Check for running DayZ server instance
							if (!$killServer)
								{
									echo "The DayZ server with PID $displayPid is not running or no longer matches the saved process metadata."
									echo "`n"
								
								#Kill server
								} else { 
											echo "Found tracked DayZ server with PID $displayPid. Shutting it down..."
											echo "`n"
									
											#Gracefull exit
											$killServer.CloseMainWindow() >$null

											#Wait briefly for a clean shutdown before forcing termination
											[void]$killServer.WaitForExit(3000)
											$killServer.Refresh()
											
											if (!$killServer.HasExited)
												{
													$killServer = Get-TrackedDayZProcess ([int] $trackedRecord.id) $trackedRecord.path ([datetime] $trackedRecord.startTime)

													if ($killServer)
														{
															$killServer | Stop-Process -Force
													
															echo "The DayZ server with PID $displayPid was force-stopped."
															echo "`n"
														} else {
																	echo "PID $displayPid no longer matched a tracked DayZ server. Force stop was cancelled."
																	echo "`n"
																}
													
												}
												
											echo "The DayZ server with PID $displayPid was stopped."
											echo "`n"
											$stoppedCount++
											
										}
						}
					
					#Clear tracked process list
					Clear-TrackedServerRecords
				}
	$script:lastServerActionSucceeded = ($stoppedCount -gt 0)
}

#Uninstall DayZ server
function ServerUninstall {
	
	echo "Uninstalling the DayZ server..."
	echo "`n"

    $serverFolder = $folder + $appFolder
	$appManifestPath = Get-SteamAppManifestPath $folder $steamApp
														
	#Uninstall DayZ server
	$proc = Start-Process -FilePath "$folder\steamcmd.exe" -ArgumentList (Get-SteamCmdUninstallArguments $steamApp) -Wait -NoNewWindow -PassThru
																											
	sleep -Seconds 1
    
    #Check if server was deleted and if not removed it forcefully
    if (Test-Path "$serverFolder")
        {
            Remove-Item -Path "$serverFolder" -Recurse -Force
        }

	$uninstallState = Resolve-DayZServerUninstallState $serverFolder $appManifestPath
	
    if ($uninstallState.ServerFolderExists -or $uninstallState.ManifestExists)
        {   																																				
	        echo "`n"
	        echo "The DayZ server uninstall did not complete successfully."
	        if ($uninstallState.ManifestExists)
	        	{
	        		echo "SteamCMD app manifest still exists at $appManifestPath"
	        		echo "`n"
	        	}
	        echo "`n"

        } else {
                    echo "`n"
	                if ($uninstallState.RemovedStaleManifest)
	                	{
	                		echo "SteamCMD left a stale app manifest behind. It was removed automatically."
	                		echo "`n"
	                	}
	                echo "The DayZ server was successfully uninstalled."
	                echo "`n"

                }
}

#Uninstall/remove DayZ Server/saved info
function Remove_menu {
	Show-MenuHeader 'Remove / Uninstall'

	echo "1) Clear saved SteamCMD path"
	echo "2) Legacy mod list path info"
	echo "3) Remove mod files"
	echo "4) Legacy launch parameters path info"
	echo "5) Uninstall DayZ server"
	echo "6) Uninstall SteamCMD"
	echo "7) Back to Main Menu"
	echo "`n"

	$select = Read-Host -Prompt 'Select an option'
	
    switch ($select)
        {
            #Remove stored path to SteamCMD folder
            1 {
                    echo "`n"
					echo "Clear saved SteamCMD path selected."
					echo "`n"
						
					$state = Get-StateConfig
					$state.steamCmdPath = $null
					Save-StateConfig $state
						
					echo "Cleared the saved SteamCMD path."
					echo "`n"
						
					Pause-BeforeMenu
					Remove_menu

                    Break
            }

            #Remove stored path to mod list file
            2 {
					echo "`n"
					echo "Legacy mod list path info selected."
					echo "`n"
					echo "Mod lists are now stored in $rootConfigPath. Use Manage Mods to add, move, or remove entries."
					echo "`n"
					Pause-BeforeMenu
					Remove_menu
					Break
            }

					#Select mod and remove it
            3 {
                    $reminder = $false
                    
                    echo "`n"
					echo "Remove mod files selected."
					echo "`n"

					#Prompt user to insert workshop id or workshop url for the mod to remove
					$rawRemMod = Read-Host -Prompt 'Enter the mod ID you want to remove'
					$rem_mod = Get-WorkshopIdFromInput $rawRemMod
					if ([string]::IsNullOrWhiteSpace($rem_mod))
						{
							echo "`n"
							echo "No valid mod ID was entered. Returning to Remove / Uninstall."
							echo "`n"
												
							Remove_menu
							Break
						}
										
					echo "`n"

					[void](SteamCMDFolder)

					#Path to SteamCMD DayZ Workshop content folder
					$workshopFolder = $folder + '\steamapps\workshop\content\221100'

					#Path to DayZ server folder
					$serverFolder = $folder + $appFolder

					#Check if selected mod folder exist in workshop folder
					if (!(Test-Path "$workshopFolder\$rem_mod"))
						{
							echo "The mod folder was not found in $workshopFolder."
							echo "`n"
												
						} else { 
									#Remove selected mod folder from workshop folder
									Remove-Item -LiteralPath "$workshopFolder\$rem_mod" -Force -Recurse
														
									echo "Removed the mod folder from $workshopFolder."
									echo "`n"

                                    $reminder = $true
								}
													
					#Check if selected mod folder exist in DayZ server folder
					if (!(Test-Path "$serverFolder\$rem_mod"))
						{
							echo "The mod folder was not found in $serverFolder."
							echo "`n"
												
						} else { 
									#Remove selected mod folder from DayZ server folder
									Remove-Item -LiteralPath "$serverFolder\$rem_mod" -Force -Recurse
														
									echo "Removed the mod folder from $serverFolder."
									echo "`n"

                                    $reminder =  $true
								}
										
					#Remove selected mod id from mod and server mode lists
					$config = Get-RootConfig
					Remove-WorkshopModFromConfig $config $rem_mod
					Save-RootConfig $config
					Update-GeneratedLaunchFromRootConfig $config
					
					if ($reminder)		
						{ 
							echo "If you no longer want to use $rem_mod, also remove it from your configured client and server mod lists."
							echo "`n"
						}
										
					Remove_menu

                    Break
            }

            #Remove stored path to user launch parameters file
            4 {
					echo "`n"
					echo "Legacy launch parameters path info selected."
					echo "`n"

					echo "Launch parameters are now stored in $rootConfigPath under launchParameters."
					echo "`n"
												
					echo "No separate JSON state path is stored anymore."
					echo "`n"
												
					Remove_menu

                    Break
            }

            #Uninstall DayZ server
            5 {
                    echo "`n"
					echo "Uninstall DayZ server selected."
					echo "`n"
														
					#Prompt user for DayZ server uninstall confirmation
					$rem_server = Read-Host -Prompt 'Uninstall the DayZ server? (yes/no)'
														
					echo "`n"	
														
					if ( ($rem_server -eq "yes") -or ($rem_server -eq "y")) 
						{ 	
							[void](SteamCMDFolder)
							[void](SteamCMDExe)
							ServerUninstall
																
						}
														
					Remove_menu

                    Break
            }

            #Uninstall SteamCMD
            6 {
                    echo "`n"
					echo "Uninstall SteamCMD selected."
					echo "`n"
																
					#Prompt user for SteamCMD uninstall confirmation
					$rem_server = Read-Host -Prompt 'Uninstall SteamCMD? This also uninstalls the DayZ server and removes all of its data. (yes/no)'
																
					echo "`n"	
														
					if ( ($rem_server -eq "yes") -or ($rem_server -eq "y")) 
						{ 	
							SteamCMDFolder
							SteamCMDExe
							ServerUninstall
																		
							echo "Uninstalling SteamCMD..."
							echo "`n"

							if (!(Test-SafeSteamCmdFolderForRemoval $folder))
								{
									echo "The saved path is not a safe SteamCMD install folder, so the SteamCMD folder will not be removed: $folder"
									echo "`n"
									Remove_menu
									return
								}

							$confirmFolder = Read-Host -Prompt "Type the full SteamCMD folder path to confirm removal"
							if ($confirmFolder -ne $folder)
								{
									echo "The confirmation path did not match. The SteamCMD folder was not removed."
									echo "`n"
									Remove_menu
									return
								}
																		
							Remove-Item -LiteralPath "$folder" -Force -Recurse
																		
							echo "SteamCMD was successfully uninstalled."
							echo "`n"
																		
						}
																
					#Prompt user for Documents folder removal confirmation
					$rem_mod = Read-Host -Prompt 'Remove the Documents state folder, including saved SteamCMD paths, generated launch mod strings, and tracked server process info? (yes/no)'
																
					echo "`n"	
														
					if ( ($rem_mod -eq "yes") -or ($rem_mod -eq "y")) 
						{ 	
							echo "Removing the Documents state folder..."
							echo "`n"
																		
							Remove-Item -LiteralPath "$docFolder" -Force -Recurse
																		
							echo "The folder was successfully removed."
							echo "`n"
																		
						}
																
					Remove_menu

                    Break
            }

            #Return to previous menu
            7 {
                    Menu

                    Break
            }

            #Force user to select one of provided options
            Default {
                        echo "`n"
						echo "Select a number from the list (1-7)."
						echo "`n"
																				
						Remove_menu
            }

        }

}

#When launch parameters are used
#Parameters are described in README.md and Get-Help
function CMD {
	
	#Prepare variables for correct parameter value check
	$paramCheckUpdate = $false
	$paramCheckServer = $false
	
	echo "`n"
	echo "Command-line parameters detected."

    #Set Steam app id and server folder name
	if ($app -eq "exp") 
		{ 
            echo "`n"
			echo "Experimental server selected."
			echo "`n"

			Set-SelectedServerApp 'exp'

        } else {

                    echo "`n"
			        echo "Stable server selected."
			        echo "`n"

					Set-SelectedServerApp 'stable'

                }
	
	#Call server update and related functions
	if (($u -eq "server") -or ($update -eq "server")) 
		{ 
			echo "`n"
			echo "Update server selected."
			echo "`n"
			
			$select = 1
			
			[void](SteamCMDFolder)
			[void](SteamCMDExe)
			SteamLogin
				
			$paramCheckUpdate = $true
				
			
			#Call mods update and related functions		
			} elseif (($u -eq "mod") -or ($u -eq "mods") -or ($update -eq "mod") -or ($update -eq "mods"))
					{ 
						echo "`n"
						echo "Update mods selected."
						echo "`n"
						
						$select = 2
						
						[void](SteamCMDFolder)
						[void](SteamCMDExe)
						SteamLogin
							
						$paramCheckUpdate = $true
							
						
						#Call both server and mods updates 
						} elseif (($u -eq "all") -or ($update -eq "all"))
								{ 
									echo "`n"
									echo "Update server and mods selected."
									echo "`n"
									
									#Server update
									$select = 1
			
									[void](SteamCMDFolder)
									[void](SteamCMDExe)
									SteamLogin
									
									#Mods update
									$select = 2
									
									SteamLogin
									
									$paramCheckUpdate = $true
									
								}
	#Start DayZ server							
	if (($s -eq "start") -or ($server -eq "start")) 
		{ 
			echo "`n"
								
			[void](SteamCMDFolder)
			
			$paramCheckServer = $true
			
			#Check which launch parameter file to use
			#User launch parameters
			if (($lp -eq "user") -or ($launchParam -eq "user")) 
				{ 
					echo "Start server with saved launch parameters selected."
					
					$select = 1
					
					Server_menu
					
					#Default launch parameters
					} else {
								echo "Start server with default launch parameters selected."
								
								$select = 2
					
								Server_menu
							}
				
			#Stop running server	
			} elseif (($s -eq "stop") -or ($server -eq "stop"))
					{ 	
						echo "`n"
						echo "Stop server selected."
						echo "`n"
										
						ServerStop
						
						$paramCheckServer = $true

					}

	#Check for wrong launch parameter values
	if (($paramCheckUpdate -eq $false) -or ($paramCheckServer -eq $false))
		{ 
			if ((($paramCheckUpdate -eq $false) -and !($u -eq "")) -or (($paramCheckUpdate -eq $false) -and !($update -eq ""))) 
				{ 
					echo "`n"
					echo "Invalid -u/-update value. See README.md or 'Get-Help .\Server_manager.ps1 -Parameter update' for valid launch parameter values."
					echo "`n"
				}
				
			if ((($paramCheckServer -eq $false) -and !($s -eq "")) -or (($paramCheckServer -eq $false) -and !($server -eq ""))) 
				{ 
					echo "`n"
					echo "Invalid -s/-server value. See README.md or 'Get-Help .\Server_manager.ps1 -Parameter server' for valid launch parameter values."
					echo "`n"
				}
			
			exit 0
		}
			
	echo "All requested tasks are complete."
	echo "`n"
	
	exit 0
}


function MainMenu {

		Show-MenuHeader (Get-MainMenuTitle)

	    echo "1) Stable server"
	    echo "2) Experimental server"
        echo "3) Exit"
	    echo "`n"

	    $select = Read-Host -Prompt 'Select an option'
	
        switch ($select)
            {
                #Steam Stable server app
                1 {
                    echo "`n"
			        echo "Stable server selected."
			        echo "`n"

					Set-SelectedServerApp 'stable'
			
			        Menu

                    Break
                } 

                #Steam Experimental server app
                2 {
                    echo "`n"
				    echo "Experimental server selected."
				    echo "`n"

					Set-SelectedServerApp 'exp'
						
				    Menu

                    Break
                }

                #Close script
                3 {
                    echo "`n"
				    echo "Exit selected."
				    echo "`n"
														
				    exit 0

                    Break
                }

                #Force user to select one of provided options
                Default {
                            echo "`n"
						    echo "Select a number from the list (1-3)."
						    echo "`n"
																				
							Pause-BeforeMenu
						    MainMenu
                }
	    }
}

#Open Main menu if launch parameters are not used
if (!$script:ServerManagerSkipAutoRun)
	{
		Initialize-ConfigFiles

		if (($u -eq "") -and ($update -eq "") -and ($s -eq "") -and ($server -eq ""))
			{
				if (Run-InteractiveSteamCmdSetup)
					{
						MainMenu
					}

			} else {
						#Run CMD function when launch parameters are used
						CMD

					}

		exit 0
	}
# SIG # Begin signature block
# MIIcZwYJKoZIhvcNAQcCoIIcWDCCHFQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUJGaUFA3dh1nuwSV6iEEgPK1Z
# yQOggheRMIIE8TCCA9mgAwIBAgIQPLyHe5m6GFiJpDaKnGk42TANBgkqhkiG9w0B
# AQsFADB/MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRp
# b24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxMDAuBgNVBAMTJ1N5
# bWFudGVjIENsYXNzIDMgU0hBMjU2IENvZGUgU2lnbmluZyBDQTAeFw0xOTA0MzAw
# MDAwMDBaFw0yMjA1MDcyMzU5NTlaMIGIMQswCQYDVQQGEwJDWjEZMBcGA1UECAwQ
# U3RyZWRvY2Vza3kga3JhajEYMBYGA1UEBwwPTW5pc2VrIHBvZCBCcmR5MSEwHwYD
# VQQKDBhCT0hFTUlBIElOVEVSQUNUSVZFIGEucy4xITAfBgNVBAMMGEJPSEVNSUEg
# SU5URVJBQ1RJVkUgYS5zLjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# ALnwscZ1gIwHNKD5OAfX/6HYpkh1lfaqYiDuomVQji5IvD0dsPqdiCN9+4AuI7wF
# og05Qp/dFpvEmF6E0WiP+nw6dt7wnoQ4tipZKkHSw7SJkp4zlQxAqvMGwd5x6RMP
# cLjEKA8CEadG1dM3+x7Evm27QxbEwGYSE45Qz0DBYDQoD9njyvA83DQGXpbxR69K
# vFRW8xcTFnVshYvLRx9EurrakweWYtIv1DGFfZKwqpx+DYHemztGVAlQWDo8yCcq
# 6wIOU8xi4NMsYpiIgGxUhG1nriS2DKXPRcVpldF0lJdfh7lSS+Wb4L/JQAqt47pD
# DmD1AjHc6FGpDFzsBnrfjP0CAwEAAaOCAV0wggFZMAkGA1UdEwQCMAAwDgYDVR0P
# AQH/BAQDAgeAMCsGA1UdHwQkMCIwIKAeoByGGmh0dHA6Ly9zdi5zeW1jYi5jb20v
# c3YuY3JsMGEGA1UdIARaMFgwVgYGZ4EMAQQBMEwwIwYIKwYBBQUHAgEWF2h0dHBz
# Oi8vZC5zeW1jYi5jb20vY3BzMCUGCCsGAQUFBwICMBkMF2h0dHBzOi8vZC5zeW1j
# Yi5jb20vcnBhMBMGA1UdJQQMMAoGCCsGAQUFBwMDMFcGCCsGAQUFBwEBBEswSTAf
# BggrBgEFBQcwAYYTaHR0cDovL3N2LnN5bWNkLmNvbTAmBggrBgEFBQcwAoYaaHR0
# cDovL3N2LnN5bWNiLmNvbS9zdi5jcnQwHwYDVR0jBBgwFoAUljtT8Hkzl699g+8u
# K8zKt4YecmYwHQYDVR0OBBYEFMa2/MDoNhLIzM6lAKuSUC9oHzgZMA0GCSqGSIb3
# DQEBCwUAA4IBAQBf2J8DPInPPgYsJgtd8S20hrsO2HAdJHBX5UwPwp0XdL2X25G2
# 50qdUgmWYHnPa0nmVW7q+oRJ9rJFKar2uQlbnBA2hh2tatG8EjPJGT7Si2IEy5aP
# QO/eStKX5sNxufChKfEgF4TUAWch/yJkJH6JX2QNWKaWtZvxyYQefqjFwO7xY90e
# dcDkIWEUfWkUGEJiT5T5HlS4VLXPzd6pc2sUn2LGq5be3SU/HTsZ/5gWFG1XQoMD
# lUoXGks9q5TjqO8mrWZcEEq3TBTZEFyYkVBN2kaSCN8EBcetZIsv8Q9AtBYBbsHn
# 8yYsWSfU6ZfbHQsdnBE4/GFppwPb+5G8d8m6MIIFWTCCBEGgAwIBAgIQPXjX+XZJ
# YLJhffTwHsqGKjANBgkqhkiG9w0BAQsFADCByjELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3
# b3JrMTowOAYDVQQLEzEoYykgMjAwNiBWZXJpU2lnbiwgSW5jLiAtIEZvciBhdXRo
# b3JpemVkIHVzZSBvbmx5MUUwQwYDVQQDEzxWZXJpU2lnbiBDbGFzcyAzIFB1Ymxp
# YyBQcmltYXJ5IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IC0gRzUwHhcNMTMxMjEw
# MDAwMDAwWhcNMjMxMjA5MjM1OTU5WjB/MQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5l
# dHdvcmsxMDAuBgNVBAMTJ1N5bWFudGVjIENsYXNzIDMgU0hBMjU2IENvZGUgU2ln
# bmluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJeDHgAWryyx
# 0gjE12iTUWAecfbiR7TbWE0jYmq0v1obUfejDRh3aLvYNqsvIVDanvPnXydOC8KX
# yAlwk6naXA1OpA2RoLTsFM6RclQuzqPbROlSGz9BPMpK5KrA6DmrU8wh0MzPf5vm
# wsxYaoIV7j02zxzFlwckjvF7vjEtPW7ctZlCn0thlV8ccO4XfduL5WGJeMdoG68R
# eBqYrsRVR1PZszLWoQ5GQMWXkorRU6eZW4U1V9Pqk2JhIArHMHckEU1ig7a6e2iC
# Me5lyt/51Y2yNdyMK29qclxghJzyDJRewFZSAEjM0/ilfd4v1xPkOKiE1Ua4E4bC
# G53qWjjdm9sCAwEAAaOCAYMwggF/MC8GCCsGAQUFBwEBBCMwITAfBggrBgEFBQcw
# AYYTaHR0cDovL3MyLnN5bWNiLmNvbTASBgNVHRMBAf8ECDAGAQH/AgEAMGwGA1Ud
# IARlMGMwYQYLYIZIAYb4RQEHFwMwUjAmBggrBgEFBQcCARYaaHR0cDovL3d3dy5z
# eW1hdXRoLmNvbS9jcHMwKAYIKwYBBQUHAgIwHBoaaHR0cDovL3d3dy5zeW1hdXRo
# LmNvbS9ycGEwMAYDVR0fBCkwJzAloCOgIYYfaHR0cDovL3MxLnN5bWNiLmNvbS9w
# Y2EzLWc1LmNybDAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYBBQUHAwMwDgYDVR0P
# AQH/BAQDAgEGMCkGA1UdEQQiMCCkHjAcMRowGAYDVQQDExFTeW1hbnRlY1BLSS0x
# LTU2NzAdBgNVHQ4EFgQUljtT8Hkzl699g+8uK8zKt4YecmYwHwYDVR0jBBgwFoAU
# f9Nlp8Ld7LvwMAnzQzn6Aq8zMTMwDQYJKoZIhvcNAQELBQADggEBABOFGh5pqTf3
# oL2kr34dYVP+nYxeDKZ1HngXI9397BoDVTn7cZXHZVqnjjDSRFph23Bv2iEFwi5z
# uknx0ZP+XcnNXgPgiZ4/dB7X9ziLqdbPuzUvM1ioklbRyE07guZ5hBb8KLCxR/Md
# oj7uh9mmf6RWpT+thC4p3ny8qKqjPQQB6rqTog5QIikXTIfkOhFf1qQliZsFay+0
# yQFMJ3sLrBkFIqBgFT/ayftNTI/7cmd3/SeUx7o1DohJ/o39KK9KEr0Ns5cF3kQM
# Ffo2KwPcwVAB8aERXRTl4r0nS1S+K4ReD6bDdAUK75fDiSKxH3fzvc1D1PFMqT+1
# i4SvZPLQFCEwggZqMIIFUqADAgECAhADAZoCOv9YsWvW1ermF/BmMA0GCSqGSIb3
# DQEBBQUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3Vy
# ZWQgSUQgQ0EtMTAeFw0xNDEwMjIwMDAwMDBaFw0yNDEwMjIwMDAwMDBaMEcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQKEwhEaWdpQ2VydDElMCMGA1UEAxMcRGlnaUNlcnQg
# VGltZXN0YW1wIFJlc3BvbmRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAKNkXfx8s+CCNeDg9sYq5kl1O8xu4FOpnx9kWeZ8a39rjJ1V+JLjntVaY1sC
# SVDZg85vZu7dy4XpX6X51Id0iEQ7Gcnl9ZGfxhQ5rCTqqEsskYnMXij0ZLZQt/US
# s3OWCmejvmGfrvP9Enh1DqZbFP1FI46GRFV9GIYFjFWHeUhG98oOjafeTl/iqLYt
# WQJhiGFyGGi5uHzu5uc0LzF3gTAfuzYBje8n4/ea8EwxZI3j6/oZh6h+z+yMDDZb
# esF6uHjHyQYuRhDIjegEYNu8c3T6Ttj+qkDxss5wRoPp2kChWTrZFQlXmVYwk/PJ
# YczQCMxr7GJCkawCwO+k8IkRj3cCAwEAAaOCAzUwggMxMA4GA1UdDwEB/wQEAwIH
# gDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIIBvwYDVR0g
# BIIBtjCCAbIwggGhBglghkgBhv1sBwEwggGSMCgGCCsGAQUFBwIBFhxodHRwczov
# L3d3dy5kaWdpY2VydC5jb20vQ1BTMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4A
# eQAgAHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQA
# ZQAgAGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUA
# IABvAGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAA
# YQBuAGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcA
# cgBlAGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIA
# aQBsAGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQA
# ZQBkACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsG
# CWCGSAGG/WwDFTAfBgNVHSMEGDAWgBQVABIrE5iymQftHt+ivlcNK2cCzTAdBgNV
# HQ4EFgQUYVpNJLZJMp1KKnkag0v0HonByn0wfQYDVR0fBHYwdDA4oDagNIYyaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcmww
# OKA2oDSGMmh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RENBLTEuY3JsMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURDQS0xLmNydDANBgkqhkiG9w0BAQUF
# AAOCAQEAnSV+GzNNsiaBXJuGziMgD4CH5Yj//7HUaiwx7ToXGXEXzakbvFoWOQCd
# 42yE5FpA+94GAYw3+puxnSR+/iCkV61bt5qwYCbqaVchXTQvH3Gwg5QZBWs1kBCg
# e5fH9j/n4hFBpr1i2fAnPTgdKG86Ugnw7HBi02JLsOBzppLA044x2C/jbRcTBu7k
# A7YUq/OPQ6dxnSHdFMoVXZJB2vkPgdGZdA0mxA5/G7X1oPHGdwYoFenYk+VVFvC7
# Cqsc21xIJ2bIo4sKHOWV2q7ELlmgYd3a822iYemKC23sEhi991VUQAOSK2vCUcIK
# SK+w1G7g9BQKOhvjjz3Kr2qNe9zYRDCCBs0wggW1oAMCAQICEAb9+QOWA63qAArr
# Pye7uhswDQYJKoZIhvcNAQEFBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMb
# RGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTA2MTExMDAwMDAwMFoXDTIx
# MTExMDAwMDAwMFowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# QXNzdXJlZCBJRCBDQS0xMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# 6IItmfnKwkKVpYBzQHDSnlZUXKnE0kEGj8kz/E1FkVyBn+0snPgWWd+etSQVwpi5
# tHdJ3InECtqvy15r7a2wcTHrzzpADEZNk+yLejYIA6sMNP4YSYL+x8cxSIB8HqIP
# kg5QycaH6zY/2DDD/6b3+6LNb3Mj/qxWBZDwMiEWicZwiPkFl32jx0PdAug7Pe2x
# QaPtP77blUjE7h6z8rwMK5nQxl0SQoHhg26Ccz8mSxSQrllmCsSNvtLOBq6thG9I
# hJtPQLnxTPKvmPv2zkBdXPao8S+v7Iki8msYZbHBc63X8djPHgp0XEK4aH631XcK
# J1Z8D2KkPzIUYJX9BwSiCQIDAQABo4IDejCCA3YwDgYDVR0PAQH/BAQDAgGGMDsG
# A1UdJQQ0MDIGCCsGAQUFBwMBBggrBgEFBQcDAgYIKwYBBQUHAwMGCCsGAQUFBwME
# BggrBgEFBQcDCDCCAdIGA1UdIASCAckwggHFMIIBtAYKYIZIAYb9bAABBDCCAaQw
# OgYIKwYBBQUHAgEWLmh0dHA6Ly93d3cuZGlnaWNlcnQuY29tL3NzbC1jcHMtcmVw
# b3NpdG9yeS5odG0wggFkBggrBgEFBQcCAjCCAVYeggFSAEEAbgB5ACAAdQBzAGUA
# IABvAGYAIAB0AGgAaQBzACAAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBvAG4A
# cwB0AGkAdAB1AHQAZQBzACAAYQBjAGMAZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQA
# aABlACAARABpAGcAaQBDAGUAcgB0ACAAQwBQAC8AQwBQAFMAIABhAG4AZAAgAHQA
# aABlACAAUgBlAGwAeQBpAG4AZwAgAFAAYQByAHQAeQAgAEEAZwByAGUAZQBtAGUA
# bgB0ACAAdwBoAGkAYwBoACAAbABpAG0AaQB0ACAAbABpAGEAYgBpAGwAaQB0AHkA
# IABhAG4AZAAgAGEAcgBlACAAaQBuAGMAbwByAHAAbwByAGEAdABlAGQAIABoAGUA
# cgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUAcgBlAG4AYwBlAC4wCwYJYIZIAYb9bAMV
# MBIGA1UdEwEB/wQIMAYBAf8CAQAweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQw
# gYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwHQYDVR0OBBYEFBUA
# EisTmLKZB+0e36K+Vw0rZwLNMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3z
# bcgPMA0GCSqGSIb3DQEBBQUAA4IBAQBGUD7Jtygkpzgdtlspr1LPUukxR6tWXHvV
# DQtBs+/sdR90OPKyXGGinJXDUOSCuSPRujqGcq04eKx1XRcXNHJHhZRW0eu7NoR3
# zCSl8wQZVann4+erYs37iy2QwsDStZS9Xk+xBdIOPRqpFFumhjFiqKgz5Js5p8T1
# zh14dpQlc+Qqq8+cdkvtX8JLFuRLcEwAiR78xXm8TBJX/l/hHrwCXaj++wc4Tw3G
# XZG5D2dFzdaD7eeSDY2xaYxP+1ngIw/Sqq4AfO6cQg7PkdcntxbuD8O9fAqg7iwI
# VYUiuOsYGk38KiGtSTGDR5V3cdyxG0tLHBCcdxTBnU8vWpUIKRAmMYIEQDCCBDwC
# AQEwgZMwfzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0
# aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMTAwLgYDVQQDEydT
# eW1hbnRlYyBDbGFzcyAzIFNIQTI1NiBDb2RlIFNpZ25pbmcgQ0ECEDy8h3uZuhhY
# iaQ2ipxpONkwCQYFKw4DAhoFAKBwMBAGCisGAQQBgjcCAQwxAjAAMBkGCSqGSIb3
# DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEV
# MCMGCSqGSIb3DQEJBDEWBBTa+6rb6zq4va07MPoV2/88kByOvTANBgkqhkiG9w0B
# AQEFAASCAQALP+N/tqR0/Qw451i4fsXK/Cr+XcuRTqivAnlfJbHvZI11NSxwQ03X
# KY2qu60+wg0Gfl/ZwwAznN1IUFUyBObCmmFoF7lxABUOnT7/mlKQCPQ4JPFlI1kK
# 1F6DhsS9LAIAsci1IClXszVfWFCZ/1JYvh3aRF+dN5s04jqXOqpInSTOskbyB6ad
# 1u9EessQSZJFqJolkookkIov8xhxcF7UOH/FZfzKhDnJvITS7x4cbH01CAuvAdCO
# WenI8WeZVLJHajWnrZ9V1JJda2BQoWbDf6I9LOsavGy/s6MiopjUg4RvS72D8L0N
# msDnj3u7ydVYfJ+67pPW/zGyd++wsG4RoYICDzCCAgsGCSqGSIb3DQEJBjGCAfww
# ggH4AgEBMHYwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgQXNz
# dXJlZCBJRCBDQS0xAhADAZoCOv9YsWvW1ermF/BmMAkGBSsOAwIaBQCgXTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMDAzMjYxMjA0
# MzVaMCMGCSqGSIb3DQEJBDEWBBRF8BlvtZC95yC6p4E/UqSASV633zANBgkqhkiG
# 9w0BAQEFAASCAQAo8I30sVb5ntMYgCRot1euFD41ojwoESSRh85mxXK3Oj+vREpb
# ZxD2OgDnvwFlxzgsQrENSg+bIveT8w4boW/Owt3b/kOmuqb9I6DwK4RQOlYYp56z
# zA0YkwS03lA5sZKxvsvsWJwX4ZBdpzibwRs6RX4cJvgPJgD0yfVwWwxyKUqAdggx
# lWpGyzUrk43QbfbLamlJ0yro/iud5fbNps0F3b3e+nzqkn4NFz0JdqwevnPMXXXN
# UbJ0g5+qJZdKBwjgPqSlDECThZHeapzKNMVof9yx+H3gd4IiE9Awg8JvCvJ+e0Y3
# jptZrzTzeVAv7ukQhZjhqD9IFtgNXOXot49/
# SIG # End signature block
