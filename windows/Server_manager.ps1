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
$docFolder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'DayZ_Server'
$steamDoc = $docFolder + '\SteamCmdPath.txt'
$modListPath = $docFolder + '\modListPath.txt'
$serverModListPath = $docFolder + '\serverModListPath.txt'
$modServerPar = $docFolder + '\modServerPar.txt'
$serverModServerPar = $docFolder + '\serverModServerPar.txt'
$userServerParPath = $docFolder + '\userServerParPath.txt'
$pidServer = $docFolder + '\pidServer.txt'
$tempModList = $docFolder + '\tempModList.txt'
$tempModListServer = $docFolder + '\tempModListServer.txt'
$tempLoginScript = $docFolder + '\steamcmd-login.tmp'
$rootConfigPath = Join-Path $docFolder 'server-manager.config.json'
$stateConfigPath = Join-Path $docFolder 'server-manager.state.json'

#Prepare variables related to SteamCMD folder
$steamApp = $null
$appFolder = $null
$folder = $null
$loadMods = $null
$script:startupBootstrapActive = $false
$script:serverManagerVersion = '1.1.0'
$script:lastServerActionSucceeded = $false
$script:lastHybridBackendStatus = 'Not checked'
$script:steamCmdSessionCredential = $null
$script:steamCmdRetryCredentialResolver = { Request-SteamCmdRetryCredential }


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

function Test-HybridPythonExecutable {
	param(
		[Parameter(Mandatory = $true)][string] $Command,
		[string[]] $PrefixArgs = @()
	)

	if (-not (Get-Command $Command -ErrorAction SilentlyContinue))
		{
			return $false
		}

	try
		{
			$invokeArgs = @($PrefixArgs) + @('-c', "import sys; sys.stdout.write('DZSM_PYOK')")
			$output = & $Command @invokeArgs 2>$null
			$text = ([string]::Join('', @($output))).Trim()
			return ($LASTEXITCODE -eq 0 -and $text -eq 'DZSM_PYOK')
		}
	catch
		{
			return $false
		}
}

function Get-HybridPythonCommandSpec {
	$override = [string] $env:DAYZ_SERVER_MANAGER_PYTHON
	if (-not [string]::IsNullOrWhiteSpace($override))
		{
			if (Test-HybridPythonExecutable -Command $override)
				{
					return [pscustomobject]@{
						Command    = $override
						PrefixArgs = @()
					}
				}

			return $null
		}

	foreach ($candidate in @(
		[pscustomobject]@{ Command = 'python'; PrefixArgs = @() },
		[pscustomobject]@{ Command = 'python3'; PrefixArgs = @() },
		[pscustomobject]@{ Command = 'py'; PrefixArgs = @('-3') }
	))
		{
			if (Test-HybridPythonExecutable -Command $candidate.Command -PrefixArgs $candidate.PrefixArgs)
				{
					return $candidate
				}
		}

	return $null
}

function Get-HybridPythonInstallCommand {
	if (Get-Command 'winget' -ErrorAction SilentlyContinue)
		{
			return 'winget install -e --id Python.Python.3.12'
		}

	return 'winget install -e --id Python.Python.3.12'
}

function Test-HybridPythonPrerequisite {
	$commandSpec = Get-HybridPythonCommandSpec
	if ($commandSpec)
		{
			return $true
		}

	Write-Host 'Python 3 is required for the hybrid DayZ Server Manager backend.'
	Write-Host "Install it with:"
	Write-Host "  $(Get-HybridPythonInstallCommand)"
	Write-Host ''
	return $false
}

function Invoke-HybridPythonCore {
	param([string[]] $Arguments)

	$commandSpec = Get-HybridPythonCommandSpec
	if (!$commandSpec)
		{
			return $null
		}

	$repoRoot = Split-Path $PSScriptRoot -Parent

	Push-Location $repoRoot
	try
		{
			$output = @(& $commandSpec.Command @($commandSpec.PrefixArgs + @('-m', 'dayz_manager.cli') + $Arguments) 2>$null)
			if ($LASTEXITCODE -ne 0)
				{
					return $null
				}

			return ([string]::Join([Environment]::NewLine, @($output))).TrimEnd("`r", "`n")
		}
	catch
		{
			return $null
		}
	finally
		{
			Pop-Location
		}
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
	$steamLoginStatus = Get-SteamCmdCredentialStatus
	$script:lastHybridBackendStatus = 'Not checked'

	Write-Host " Status"
	Write-Host " $([string]::new([char]0x2500, 37))"
	Write-Host "  Server    : " -NoNewline
	if ($serverStatus -eq 'Running')
		{
			Write-Host $serverStatus -ForegroundColor Green
		} else {
					Write-Host $serverStatus -ForegroundColor Yellow
				}
	Write-Host "  Directory : $serverDirectory"
	Write-Host "  Account   : $steamLoginStatus"

	$config = Get-RootConfig
	if ($config)
		{
			$summary = Get-GroupStatusSummaryFromConfig $config
			if ($summary.groupState -eq 'none')
				{
					Write-Host "  Active group : " -NoNewline
					Write-Host "<none>" -ForegroundColor Yellow
				}
			else
				{
					if ($summary.groupState -eq 'missing')
						{
							Write-Host "  Active group : " -NoNewline
							Write-Host "$($summary.activeGroup) (missing)" -ForegroundColor Yellow
						}
					else
						{
							$line = "  Active group : $($summary.activeGroup)   ($($summary.clientCount) mods, $($summary.serverCount) serverMods)"
							Write-Host $line
							if ([int] $summary.danglingCount -gt 0)
								{
									Write-Host "   [!] $($summary.danglingCount) dangling id(s) - open Manage mod groups to fix" -ForegroundColor Yellow
								}
						}
				}
		}

	Write-Host " $([string]::new([char]0x2500, 37))"
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

			return $true
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

function Set-PrivateFileAcl {
    param([string] $Path)

    if (!(Test-Path -LiteralPath $Path))
        {
            return
        }

    # Use icacls to restrict access to the current user. This does not
    # require SeSecurityPrivilege. The /inheritance:r flag removes
    # inherited entries, and /grant gives the current user full control.
    # The state file contains DPAPI-encrypted blobs (already per-user),
    # so this is defense-in-depth, not the primary security boundary.
    try
        {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
            $result = & icacls $resolvedPath /inheritance:r /grant "${currentUser}:(F)" 2>&1
            if ($LASTEXITCODE -ne 0)
                {
                    Write-Warning "Could not restrict file permissions on ${Path}: $result"
                }
        }
    catch
        {
            Write-Warning "Could not restrict file permissions on ${Path}: $($_.Exception.Message)"
        }
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

function Get-WindowsRootConfigPath {
	param([string] $DocFolder = $docFolder)

	return Join-Path $DocFolder 'server-manager.config.json'
}

function Get-WindowsLegacyRootConfigPath {
	return Join-Path $PSScriptRoot 'server-manager.config.json'
}

function Invoke-WindowsRootConfigMigration {
	param(
		[string] $CanonicalPath = (Get-WindowsRootConfigPath),
		[string] $LegacyPath = (Get-WindowsLegacyRootConfigPath)
	)

	if (Test-Path -LiteralPath $CanonicalPath)
		{
			return $false
		}

	if (!(Test-Path -LiteralPath $LegacyPath))
		{
			return $false
		}

	$canonicalFolder = Split-Path -Parent $CanonicalPath
	if (-not [string]::IsNullOrWhiteSpace($canonicalFolder) -and -not (Test-Path -LiteralPath $canonicalFolder))
		{
			New-Item -ItemType Directory -Path $canonicalFolder -Force | Out-Null
		}

	$backupPath = "$LegacyPath.legacy.bak"
	Copy-Item -LiteralPath $LegacyPath -Destination $CanonicalPath -Force
	Move-Item -LiteralPath $LegacyPath -Destination $backupPath -Force
	Write-Host "Migrated legacy Windows config to the Documents location."

	return $true
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

function Resolve-LegacyFilePath {
	param(
		[string] $PathReferenceFile,
		[string] $FallbackPath
	)

	# Check the path-reference file first (e.g. modListPath.txt contains a path to the actual mod_list.txt)
	if (![string]::IsNullOrWhiteSpace($PathReferenceFile) -and (Test-Path -LiteralPath $PathReferenceFile))
		{
			$referencedPath = (Get-Content -LiteralPath $PathReferenceFile -Raw).Trim()
			if (![string]::IsNullOrWhiteSpace($referencedPath))
				{
					# Handle relative paths by resolving against script root
					if ($referencedPath -notmatch '^[A-Za-z]:\\' -and $referencedPath -notmatch '^\\\\')
						{
							$referencedPath = Join-Path $PSScriptRoot $referencedPath
						}

					if (Test-Path -LiteralPath $referencedPath)
						{
							return [pscustomobject]@{
								Path = $referencedPath
								Source = 'reference'
							}
						}
				}
		}

	# Fall back to the hardcoded location
	if (![string]::IsNullOrWhiteSpace($FallbackPath) -and (Test-Path -LiteralPath $FallbackPath))
		{
			return [pscustomobject]@{
				Path = $FallbackPath
				Source = 'fallback'
			}
		}

	return $null
}

function Initialize-RootConfig {
	param(
		[string] $RootPath,
		[string] $ConfigPath,
		[string] $DocFolder = $null
	)

	if (Test-Path -LiteralPath $ConfigPath)
		{
			return @()
		}

	$report = @()

	# Resolve launch parameters file
	$launchResolved = $null
	if ($DocFolder)
		{
			$launchResolved = Resolve-LegacyFilePath (Join-Path $DocFolder 'userServerParPath.txt') (Join-Path $RootPath 'launch_params.txt')
		} else {
			$fallback = Join-Path $RootPath 'launch_params.txt'
			if (Test-Path -LiteralPath $fallback)
				{
					$launchResolved = [pscustomobject]@{ Path = $fallback; Source = 'fallback' }
				}
		}

	$launchParameters = '-config=serverDZ.cfg "-mod=" "-serverMod=" "-profiles=<DayZServerPath>\logs" -port=2302 -freezecheck -adminlog -dologs'
	if ($launchResolved)
		{
			$launchParameters = (Get-Content -LiteralPath $launchResolved.Path -Raw).Trim()
			$report += [pscustomobject]@{
				fileName    = [System.IO.Path]::GetFileName($launchResolved.Path)
				sourcePath  = $launchResolved.Path
				targetFile  = 'server-manager.config.json'
				description = 'Launch parameters'
			}
		}

	# Resolve client mod list
	$modResolved = $null
	if ($DocFolder)
		{
			$modResolved = Resolve-LegacyFilePath (Join-Path $DocFolder 'modListPath.txt') (Join-Path $RootPath 'mod_list.txt')
		} else {
			$fallback = Join-Path $RootPath 'mod_list.txt'
			if (Test-Path -LiteralPath $fallback)
				{
					$modResolved = [pscustomobject]@{ Path = $fallback; Source = 'fallback' }
				}
		}

	$mods = @()
	if ($modResolved)
		{
			$mods = Convert-LegacyModList (Get-Content -LiteralPath $modResolved.Path)
			$report += [pscustomobject]@{
				fileName    = [System.IO.Path]::GetFileName($modResolved.Path)
				sourcePath  = $modResolved.Path
				targetFile  = 'server-manager.config.json'
				description = "Client mod list ($(@($mods).Count) mod(s))"
			}
		}

	# Resolve server mod list
	$serverModResolved = $null
	if ($DocFolder)
		{
			$serverModResolved = Resolve-LegacyFilePath (Join-Path $DocFolder 'serverModListPath.txt') (Join-Path $RootPath 'server_mod_list.txt')
		} else {
			$fallback = Join-Path $RootPath 'server_mod_list.txt'
			if (Test-Path -LiteralPath $fallback)
				{
					$serverModResolved = [pscustomobject]@{ Path = $fallback; Source = 'fallback' }
				}
		}

	$serverMods = @()
	if ($serverModResolved)
		{
			$serverMods = Convert-LegacyModList (Get-Content -LiteralPath $serverModResolved.Path)
			$report += [pscustomobject]@{
				fileName    = [System.IO.Path]::GetFileName($serverModResolved.Path)
				sourcePath  = $serverModResolved.Path
				targetFile  = 'server-manager.config.json'
				description = "Server mod list ($(@($serverMods).Count) mod(s))"
			}
		}

	$config = [pscustomobject]@{
		launchParameters = $launchParameters
		mods = @($mods)
		serverMods = @($serverMods)
	}

	Save-JsonFile $ConfigPath $config

	# Backup resolved data files
	if ($launchResolved) { Backup-LegacyConfigFile $launchResolved.Path }
	if ($modResolved) { Backup-LegacyConfigFile $modResolved.Path }
	if ($serverModResolved) { Backup-LegacyConfigFile $serverModResolved.Path }

	# Backup path-reference files in DocFolder
	if ($DocFolder)
		{
			Backup-LegacyConfigFile (Join-Path $DocFolder 'modListPath.txt')
			Backup-LegacyConfigFile (Join-Path $DocFolder 'serverModListPath.txt')
			Backup-LegacyConfigFile (Join-Path $DocFolder 'userServerParPath.txt')
		}

	return @($report)
}

function Invoke-ModGroupsMigration {
	param($Config)

	if (!$Config) { return $false }

	$hasGroups = $Config.PSObject.Properties.Name -contains 'modGroups' -and $Config.modGroups
	if ($hasGroups)
		{
			if (-not ($Config.PSObject.Properties.Name -contains 'activeGroup'))
				{
					$firstName = if (@($Config.modGroups).Count -gt 0) { [string] $Config.modGroups[0].name } else { '' }
					$Config | Add-Member -NotePropertyName activeGroup -NotePropertyValue $firstName -Force
					return $true
				}
			return $false
		}

	$modIds = @()
	$serverModIds = @()
	if ($Config.PSObject.Properties.Name -contains 'launchParameters' -and $Config.launchParameters)
		{
			$modIds = Get-ModIdsFromLaunchParameters $Config.launchParameters 'mods'
			$serverModIds = Get-ModIdsFromLaunchParameters $Config.launchParameters 'serverMods'
		}

	$mission = $null
	$serverFolder = Resolve-ServerFolderForMissions $Config
	if (-not [string]::IsNullOrWhiteSpace($serverFolder))
		{
			$serverConfigPath = Join-Path $serverFolder 'serverDZ.cfg'
			if (Test-Path -LiteralPath $serverConfigPath)
				{
					$text = Get-Content -LiteralPath $serverConfigPath -Raw -ErrorAction SilentlyContinue
					$mission = Get-MissionFolderFromServerConfigText $text
				}
		}

	$defaultGroup = New-DefaultModGroup -Name 'Default' -Mods $modIds -ServerMods $serverModIds
	if ($mission)
		{
			$defaultGroup | Add-Member -NotePropertyName mission -NotePropertyValue $mission -Force
		}
	$Config | Add-Member -NotePropertyName modGroups -NotePropertyValue @($defaultGroup) -Force
	$Config | Add-Member -NotePropertyName activeGroup -NotePropertyValue 'Default' -Force

	return $true
}

function Select-ActiveModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }

	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	if (@($groups).Count -eq 0)
		{
			Write-Host "No mod groups are defined. Use Manage mod groups to create one."
			Write-Host ""
			return
		}

	Write-Host ""
	Write-Host " Available mod groups:"
	Write-Host " $([string]::new([char]0x2500, 37))"
	for ($i = 0; $i -lt $groups.Count; $i++)
		{
			$g = $groups[$i]
			$marker = if ($config.activeGroup -eq $g.name) { '*' } else { ' ' }
			$modCount = @($g.mods).Count
			$smCount = @($g.serverMods).Count
			Write-Host "  $($i + 1)) $marker $($g.name) ($modCount mods, $smCount serverMods)"
		}
	Write-Host ""
	Write-Host " * = currently active"
	Write-Host ""

	$raw = Read-Host -Prompt 'Select a group number (or 0 to cancel)'
	if ($raw -eq '0') { return }

	$index = 0
	if (-not [int]::TryParse($raw, [ref]$index) -or $index -lt 1 -or $index -gt $groups.Count)
		{
			Write-Host "Invalid selection."
			Write-Host ""
			return
		}

	$selected = $groups[$index - 1]
	$updatedConfig = Set-ActiveModGroup $config $selected.name
	if ($updatedConfig)
		{
			$config = $updatedConfig
			Save-RootConfig $config
			Write-Host "Switched active group to '$($selected.name)'."
		}
	else
		{
			Write-Host "Could not switch to '$($selected.name)'."
		}
	Write-Host ""
}

function Initialize-StateConfig {
	param(
		[string] $StateRoot,
		[string] $StatePath,
		[string] $ConfigPath
	)

	if (Test-Path -LiteralPath $StatePath)
		{
			return @()
		}

	$report = @()

	$steamCmdPathFile = Join-Path $StateRoot 'SteamCmdPath.txt'
	$steamCmdPath = Get-StateFileValue $steamCmdPathFile
	if ($steamCmdPath)
		{
			$report += [pscustomobject]@{
				fileName    = 'SteamCmdPath.txt'
				sourcePath  = $steamCmdPathFile
				targetFile  = 'server-manager.state.json'
				description = "SteamCMD path ($steamCmdPath)"
			}
		}

	$modLaunchFile = Join-Path $StateRoot 'modServerPar.txt'
	$modLaunch = Get-StateFileValue $modLaunchFile
	if ($modLaunch)
		{
			$report += [pscustomobject]@{
				fileName    = 'modServerPar.txt'
				sourcePath  = $modLaunchFile
				targetFile  = 'server-manager.state.json'
				description = 'Generated mod launch string'
			}
		}

	$serverModLaunchFile = Join-Path $StateRoot 'serverModServerPar.txt'
	$serverModLaunch = Get-StateFileValue $serverModLaunchFile
	if ($serverModLaunch)
		{
			$report += [pscustomobject]@{
				fileName    = 'serverModServerPar.txt'
				sourcePath  = $serverModLaunchFile
				targetFile  = 'server-manager.state.json'
				description = 'Generated server mod launch string'
			}
		}

	$pidPath = Join-Path $StateRoot 'pidServer.txt'
	$trackedServers = @()
	if (Test-Path -LiteralPath $pidPath)
		{
			$trackedServers = Convert-LegacyPidRecords (Get-Content -LiteralPath $pidPath)
			if ($trackedServers.Count -gt 0)
				{
					$report += [pscustomobject]@{
						fileName    = 'pidServer.txt'
						sourcePath  = $pidPath
						targetFile  = 'server-manager.state.json'
						description = "Tracked server(s) ($($trackedServers.Count))"
					}
				}
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

	return @($report)
}

function Show-MigrationReport {
	param([object[]] $Report)

	if (!$Report -or $Report.Count -eq 0)
		{
			return
		}

	Write-Host ""
	Write-Host "========================================"
	Write-Host " Configuration Migrated"
	Write-Host "========================================"
	Write-Host ""
	Write-Host " Your legacy configuration files have been"
	Write-Host " migrated to the new JSON format."
	Write-Host ""
	Write-Host " $([string]::new([char]0x2500, 37))"

	foreach ($item in $Report)
		{
			Write-Host "  $([char]0x2713) $($item.description)" -ForegroundColor Green
			Write-Host "    $($item.sourcePath)" -ForegroundColor DarkGray
		}

	Write-Host " $([string]::new([char]0x2500, 37))"
	Write-Host ""
	Write-Host " Original files have been renamed to *.legacy.bak"
	Write-Host ""
	Write-Host " Note: Steam credentials were not stored by the" -ForegroundColor Yellow
	Write-Host " previous script. Use 'Configure SteamCMD account'" -ForegroundColor Yellow
	Write-Host " from the server menu to save your login." -ForegroundColor Yellow
	Write-Host ""

	if (Test-InteractiveMenuMode)
		{
			[void](Read-Host -Prompt ' Press Enter to continue')
		}
}

function Initialize-ConfigFiles {
	Invoke-WindowsRootConfigMigration -CanonicalPath (Get-WindowsRootConfigPath) -LegacyPath (Get-WindowsLegacyRootConfigPath) | Out-Null
	$rootReport = @(Initialize-RootConfig $PSScriptRoot $rootConfigPath $docFolder)
	$stateReport = @(Initialize-StateConfig $docFolder $stateConfigPath $rootConfigPath)
	$fullReport = @($rootReport) + @($stateReport) | Where-Object { $_ }
	Show-MigrationReport $fullReport
}

function New-DefaultStateConfig {
	return [pscustomobject]@{
		steamCmdPath = $null
		rootConfigPath = $rootConfigPath
		lastSteamCmdSignInFailed = $false
		serverSteamAuth = [pscustomobject]@{
			usernameBlob = $null
			passwordBlob = $null
		}
		generatedLaunch = [pscustomobject]@{
			mod = ''
			serverMod = ''
		}
		trackedServers = @()
		updateCheck = [pscustomobject]@{
			latestVersion = ''
			latestTag = ''
			releaseUrl = ''
			checkedAt = ''
			lastAcknowledgedVersion = ''
		}
	}
}

function Test-UpdateCheckCacheFresh {
	param(
		$UpdateCheck,
		[datetime] $Now
	)

	if (-not $UpdateCheck)
		{
			return $false
		}

	$checkedAt = [string] $UpdateCheck.checkedAt
	if ([string]::IsNullOrWhiteSpace($checkedAt))
		{
			return $false
		}

	$parsed = [datetime]::new(0)
	if (-not [datetime]::TryParse($checkedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref] $parsed))
		{
			return $false
		}

	$age = ($Now.ToUniversalTime() - $parsed)
	return ($age.TotalHours -lt 6)
}

function Compare-UpdateCheckVersion {
	param(
		[string] $Left,
		[string] $Right
	)

	$pattern = '^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$'
	$leftMatch = [regex]::Match($Left, $pattern)
	$rightMatch = [regex]::Match($Right, $pattern)
	if (-not $leftMatch.Success -or -not $rightMatch.Success)
		{
			return $null
		}

	for ($i = 1; $i -le 3; $i++)
		{
			$leftPart = [int] $leftMatch.Groups[$i].Value
			$rightPart = [int] $rightMatch.Groups[$i].Value
			if ($leftPart -lt $rightPart) { return -1 }
			if ($leftPart -gt $rightPart) { return 1 }
		}

	return 0
}

function Test-UpdateCheckShouldNotify {
	param($UpdateCheck, [string] $CurrentVersion)

	if (-not $UpdateCheck) { return $false }
	$latest = [string] $UpdateCheck.latestVersion
	if ([string]::IsNullOrWhiteSpace($latest)) { return $false }

	$cmp = Compare-UpdateCheckVersion $CurrentVersion $latest
	if ($null -eq $cmp) { return $false }
	if ($cmp -ge 0) { return $false }

	return ([string] $UpdateCheck.lastAcknowledgedVersion -ne $latest)
}

function Test-UpdateCheckShouldShowIndicator {
	param($UpdateCheck, [string] $CurrentVersion)

	if (-not $UpdateCheck) { return $false }
	$latest = [string] $UpdateCheck.latestVersion
	if ([string]::IsNullOrWhiteSpace($latest)) { return $false }

	$cmp = Compare-UpdateCheckVersion $CurrentVersion $latest
	if ($null -eq $cmp) { return $false }
	return ($cmp -lt 0)
}

function Set-UpdateCheckAcknowledged {
	param($State, [string] $Version)

	if (-not $State) { return }
	if (-not $State.updateCheck) { return }
	$State.updateCheck.lastAcknowledgedVersion = $Version
}

function Format-UpdateCheckTimestamp {
	param([datetime] $Value)
	return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Merge-UpdateCheckResult {
	param($State, $Result, [datetime] $Now)

	if (-not $State -or -not $State.updateCheck) { return }
	if (-not $Result) { return }

	$State.updateCheck.checkedAt = Format-UpdateCheckTimestamp $Now

	if ($Result.error)
		{
			return
		}

	$newLatest = [string] $Result.latestVersion
	$previousLatest = [string] $State.updateCheck.latestVersion

	$State.updateCheck.latestVersion = $newLatest
	$State.updateCheck.latestTag = [string] $Result.latestTag
	$State.updateCheck.releaseUrl = [string] $Result.releaseUrl

	if ($newLatest -ne $previousLatest)
		{
			$State.updateCheck.lastAcknowledgedVersion = ''
		}
}

function Invoke-UpdateCheckRefresh {
	param([string] $CurrentVersion)

	$raw = Invoke-HybridPythonCore @('check-update', '--current-version', $CurrentVersion)
	if ([string]::IsNullOrWhiteSpace($raw))
		{
			return $null
		}

	try
		{
			return ($raw | ConvertFrom-Json)
		}
	catch
		{
			return $null
		}
}

function Format-UpdateCheckNoticeLines {
	param([string] $CurrentVersion, [string] $LatestVersion, [string] $ReleaseUrl)

	$lines = @(
		'========================================',
		' DayZ Server Manager - Update Available',
		'========================================',
		'',
		"A new version is available: v$LatestVersion",
		"You are running: v$CurrentVersion",
		''
	)

	if (-not [string]::IsNullOrWhiteSpace($ReleaseUrl))
		{
			$lines += "Release notes: $ReleaseUrl"
			$lines += ''
		}

	$lines += 'Press Enter to continue...'
	return $lines
}

function Format-UpdateCheckIndicator {
	param([string] $CurrentVersion, [string] $LatestVersion)

	if ([string]::IsNullOrWhiteSpace($LatestVersion)) { return '' }
	return ('* Update available: v{0} (current v{1})' -f $LatestVersion, $CurrentVersion)
}

function Show-UpdateCheckNotice {
	param([string] $CurrentVersion, [string] $LatestVersion, [string] $ReleaseUrl)

	Clear-MenuScreen
	foreach ($line in (Format-UpdateCheckNoticeLines $CurrentVersion $LatestVersion $ReleaseUrl))
		{
			Write-Host $line
		}
	$null = Read-Host
}

function Invoke-UpdateCheckStartup {
	if (-not (Test-InteractiveMenuMode)) { return }

	$state = Get-StateConfig
	$now = Get-Date

	if (-not (Test-UpdateCheckCacheFresh $state.updateCheck $now))
		{
			$result = Invoke-UpdateCheckRefresh $script:serverManagerVersion
			if ($result)
				{
					Merge-UpdateCheckResult $state $result $now
					Save-StateConfig $state
				}
		}

	if (Test-UpdateCheckShouldNotify $state.updateCheck $script:serverManagerVersion)
		{
			Show-UpdateCheckNotice $script:serverManagerVersion $state.updateCheck.latestVersion $state.updateCheck.releaseUrl
			Set-UpdateCheckAcknowledged $state $state.updateCheck.latestVersion
			Save-StateConfig $state
		}
}

function Test-UpdateApplyAvailable {
	param($State, [string] $CurrentVersion)

	if (-not $State -or -not $State.updateCheck) { return $false }
	$tag = [string] $State.updateCheck.latestTag
	$latest = [string] $State.updateCheck.latestVersion
	if ([string]::IsNullOrWhiteSpace($tag) -or [string]::IsNullOrWhiteSpace($latest)) { return $false }

	$cmp = Compare-UpdateCheckVersion $CurrentVersion $latest
	if ($null -eq $cmp) { return $false }
	return ($cmp -lt 0)
}

function Format-UpdateApplyConfirmPrompt {
	param([string] $CurrentVersion, [string] $LatestVersion)
	return "Install v$LatestVersion (current v$CurrentVersion)? You will need to restart after apply. [y/N]"
}

function Invoke-UpdateApply {
	$state = Get-StateConfig
	if (-not (Test-UpdateApplyAvailable $state $script:serverManagerVersion))
		{
			Write-Host 'No update available to install.'
			return
		}

	$tag = [string] $state.updateCheck.latestTag
	$latest = [string] $state.updateCheck.latestVersion

	Write-Host (Format-UpdateApplyConfirmPrompt $script:serverManagerVersion $latest)
	$answer = Read-Host
	if ($answer -notmatch '^(y|yes)$')
		{
			Write-Host 'Update cancelled.'
			return
		}

	$repoRoot = Split-Path $PSScriptRoot -Parent
	$raw = Invoke-HybridPythonCore @('apply-update', '--tag', $tag, '--repo-root', $repoRoot, '--timeout', '60')
	if ([string]::IsNullOrWhiteSpace($raw))
		{
			Write-Host 'Update failed: the Python backend returned no output.' -ForegroundColor Red
			return
		}

	try
		{
			$result = $raw | ConvertFrom-Json
		}
	catch
		{
			Write-Host "Update failed: could not parse backend response." -ForegroundColor Red
			return
		}

	if ($result.success)
		{
			Write-Host ("Update applied ({0} files). Please restart the manager." -f $result.appliedFiles) -ForegroundColor Green
			exit 0
		}

	Write-Host ("Update failed: {0}" -f $result.error) -ForegroundColor Red
}

function Invoke-HybridPythonCoreWithInput {
	param(
		[string[]] $Arguments,
		[string] $InputText
	)

	$commandSpec = Get-HybridPythonCommandSpec
	if (!$commandSpec)
		{
			return $null
		}

	$repoRoot = Split-Path $PSScriptRoot -Parent

	Push-Location $repoRoot
	try
		{
			$output = @($InputText | & $commandSpec.Command @($commandSpec.PrefixArgs + @('-m', 'dayz_manager.cli') + $Arguments) 2>$null)
			if ($LASTEXITCODE -ne 0)
				{
					return $null
				}

			return ([string]::Join([Environment]::NewLine, @($output))).TrimEnd("`r", "`n")
		}
	catch
		{
			return $null
		}
	finally
		{
			Pop-Location
		}
}

function Invoke-HybridJsonCommandFromConfig {
	param(
		$Config,
		[string[]] $Arguments
	)

	if (!$Config)
		{
			return $null
		}

	try
		{
			$json = ConvertTo-Json -InputObject $Config -Depth 20 -Compress
			$pythonResult = Invoke-HybridPythonCoreWithInput $Arguments $json
			if ($null -ne $pythonResult)
				{
					$parsed = ConvertFrom-Json $pythonResult
					$script:lastHybridBackendStatus = 'Python core'
					return $parsed
				}
		}
	catch
		{
		}

	$script:lastHybridBackendStatus = 'Native fallback'
	return $null
}

function Get-RootConfig {
	$config = Get-JsonFile (Get-WindowsRootConfigPath)
	if (!$config) { return $config }

	$changed = Invoke-ModGroupsMigration $config
	if ($changed)
		{
			$rootPath = Get-WindowsRootConfigPath
			$backupPath = "$rootPath.bak"
			if (-not (Test-Path -LiteralPath $backupPath))
				{
					try
						{
							Copy-Item -LiteralPath $rootPath -Destination $backupPath -Force
						}
					catch
						{
							Write-Host "Warning: could not write mod-groups migration backup: $_"
						}
				}
			Save-RootConfig $config
		}

	return $config
}

function Save-RootConfig {
	param($Config)

	Save-JsonFile (Get-WindowsRootConfigPath) $Config
}

function Backup-ImportConfigFile {
	param(
		[string] $SourcePath,
		[string] $BackupPath
	)

	if (!(Test-Path -LiteralPath $SourcePath))
		{
			return $false
		}

	try
		{
			Copy-Item -LiteralPath $SourcePath -Destination $BackupPath -Force
			return $true
		}
	catch
		{
			Write-Host "Could not create import backup '$BackupPath': $_"
			return $false
		}
}

function Export-ConfigTransferToPath {
	param(
		[string] $DestinationPath,
		[string] $ConfigPath = (Get-WindowsRootConfigPath)
	)

	if ([string]::IsNullOrWhiteSpace($DestinationPath))
		{
			return $false
		}

	$pythonResult = Invoke-HybridPythonCore @('export-config-json', '--platform', 'windows', '--config', $ConfigPath)
	if ($null -eq $pythonResult)
		{
			return $false
		}

	try
		{
			$payload = $pythonResult | ConvertFrom-Json -ErrorAction Stop
		}
	catch
		{
			Write-Host "Could not parse export payload: $_"
			return $false
		}

	Save-JsonFile $DestinationPath $payload
	return $true
}

function Import-ConfigTransferFromPath {
	param(
		[string] $SourcePath,
		[string] $ConfigPath = (Get-WindowsRootConfigPath)
	)

	if ([string]::IsNullOrWhiteSpace($SourcePath) -or !(Test-Path -LiteralPath $SourcePath))
		{
			return $false
		}

	try
		{
			$sourceText = Get-Content -LiteralPath $SourcePath -Raw
		}
	catch
		{
			Write-Host "Could not read import file '$SourcePath': $_"
			return $false
		}

	$pythonResult = Invoke-HybridPythonCoreWithInput @('import-config-json') $sourceText
	if ($null -eq $pythonResult)
		{
			return $false
		}

	try
		{
			$importedConfig = $pythonResult | ConvertFrom-Json -ErrorAction Stop
		}
	catch
		{
			Write-Host "Could not parse import payload: $_"
			return $false
		}

	if (Test-Path -LiteralPath $ConfigPath)
		{
			if (-not (Backup-ImportConfigFile -SourcePath $ConfigPath -BackupPath "$ConfigPath.import.bak"))
				{
					return $false
				}
		}

	Sync-LaunchParametersFromActiveGroup $importedConfig
	$groups = if ($importedConfig.PSObject.Properties.Name -contains 'modGroups') { @($importedConfig.modGroups) } else { @() }
	$target = Get-ModGroupByName $groups $importedConfig.activeGroup
	if ($target -and ($target.PSObject.Properties.Name -contains 'mission') -and -not [string]::IsNullOrWhiteSpace($target.mission))
		{
			Sync-ServerConfigMission $importedConfig $target.mission
		}

	Save-JsonFile $ConfigPath $importedConfig
	Update-GeneratedLaunchFromRootConfig $importedConfig
	return $true
}

function ConfigTransfer_menu {
	while ($true)
		{
			Show-MenuHeader 'Config Transfer'
			Write-Host " Use this submenu to export or import the canonical config."
			Write-Host ""
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) Export config"
			echo " 2) Import config"
			echo " 3) Back to Main Menu"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					1 {
						$destinationPath = Read-Host -Prompt 'Export destination path'
						if (Export-ConfigTransferToPath -DestinationPath $destinationPath)
							{
								Write-Host "Exported config to '$destinationPath'."
							}
						else
							{
								Write-Host "Could not export config."
							}
						Write-Host ""
						Pause-BeforeMenu
						continue
					}
					2 {
						$sourcePath = Read-Host -Prompt 'Import source path'
						if (Import-ConfigTransferFromPath -SourcePath $sourcePath)
							{
								Write-Host "Imported config from '$sourcePath'."
							}
						else
							{
								Write-Host "Could not import config."
							}
						Write-Host ""
						Pause-BeforeMenu
						continue
					}
					3 {
						return
					}
					Default {
						Write-Host ""
						Write-Host "Select a number from the list (1-3)."
						Write-Host ""
						Pause-BeforeMenu
						continue
					}
				}
		}
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
			if ($state.PSObject.Properties.Name -contains 'lastSteamCmdSignInFailed')
				{
					$normalizedState.lastSteamCmdSignInFailed = [bool] $state.lastSteamCmdSignInFailed
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
			$state = $normalizedState
		}

	# Ensure trackedServers property exists on loaded state.
	if (-not ($state.PSObject.Properties.Name -contains 'trackedServers'))
		{
			$state | Add-Member -NotePropertyName trackedServers -NotePropertyValue @() -Force
			Save-StateConfig $state
		}

	# Ensure updateCheck property exists on loaded state.
	if (-not ($state.PSObject.Properties.Name -contains 'updateCheck'))
		{
			$state | Add-Member -NotePropertyName updateCheck -NotePropertyValue ([pscustomobject]@{
				latestVersion = ''
				latestTag = ''
				releaseUrl = ''
				checkedAt = ''
				lastAcknowledgedVersion = ''
			}) -Force
			Save-StateConfig $state
		}

	# Migrate legacy Base64-encoded username blobs to DPAPI encryption.
	if ($state.PSObject.Properties.Name -contains 'serverSteamAuth' -and
		$state.serverSteamAuth -and
		$state.serverSteamAuth.PSObject.Properties.Name -contains 'usernameBlob' -and
		-not [string]::IsNullOrWhiteSpace($state.serverSteamAuth.usernameBlob))
		{
			$legacyUsername = Convert-LegacyUsernameBlob $state.serverSteamAuth.usernameBlob
			if ($legacyUsername)
				{
					$state.serverSteamAuth.usernameBlob = Protect-StateSecret $legacyUsername
					Save-StateConfig $state
				}
		}

	return $state
}

function Save-StateConfig {
	param($State)

	Save-JsonFile $stateConfigPath $State
	Set-PrivateFileAcl $stateConfigPath
}

# Encrypts a string using Windows DPAPI via ConvertFrom-SecureString.
# DPAPI scope: The encrypted blob can only be decrypted by the same
# Windows user account on the same machine. If the user profile is
# destroyed or the state file is copied to another machine, the
# credentials will need to be re-entered.
function Protect-StateSecret {
	param(
		[string] $Value
	)

	if ([string]::IsNullOrWhiteSpace($Value))
		{
			return $null
		}

	$secureValue = ConvertTo-SecureString $Value -AsPlainText -Force
	return ConvertFrom-SecureString $secureValue
}

function Unprotect-StateSecret {
	param(
		[string] $Blob
	)

	if ([string]::IsNullOrWhiteSpace($Blob))
		{
			return $null
		}

	try
		{
			$secureValue = ConvertTo-SecureString $Blob
			return (New-Object System.Management.Automation.PSCredential ('state', $secureValue)).GetNetworkCredential().Password
		}
	catch
		{
			return $null
		}
}

function Convert-LegacyUsernameBlob {
	param([string] $Blob)

	if ([string]::IsNullOrWhiteSpace($Blob))
		{
			return $null
		}

	# Try DPAPI decryption first - if it works, no migration needed.
	$dpapi = Unprotect-StateSecret $Blob
	if ($dpapi)
		{
			return $null
		}

	# Fall back to Base64 decode (the legacy format).
	try
		{
			$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Blob))
			if (![string]::IsNullOrWhiteSpace($decoded))
				{
					return $decoded
				}
		}
	catch
		{
			# Not valid Base64 either - blob is corrupted.
		}

	return $null
}

function Save-SteamCmdCredential {
	param([System.Management.Automation.PSCredential] $Credential)

	if (!$Credential)
		{
			return
		}

	$state = Get-StateConfig
	$password = $Credential.GetNetworkCredential().Password
	$credentialState = [pscustomobject]@{
		usernameBlob = Protect-StateSecret $Credential.UserName
		passwordBlob = Protect-StateSecret $password
	}
	if ($state.PSObject.Properties.Name -contains 'serverSteamAuth')
		{
			$state.serverSteamAuth = $credentialState
		} else {
			$state | Add-Member -NotePropertyName serverSteamAuth -NotePropertyValue $credentialState -Force
		}
	if ($state.PSObject.Properties.Name -contains 'lastSteamCmdSignInFailed')
		{
			$state.lastSteamCmdSignInFailed = $false
		} else {
			$state | Add-Member -NotePropertyName lastSteamCmdSignInFailed -NotePropertyValue $false -Force
		}
	Save-StateConfig $state
}

function Set-SteamCmdSessionCredential {
	param([System.Management.Automation.PSCredential] $Credential)

	$script:steamCmdSessionCredential = $Credential
}

function Get-SteamCmdSessionCredential {
	return $script:steamCmdSessionCredential
}

function Clear-SteamCmdSessionCredential {
	$script:steamCmdSessionCredential = $null
}

function Get-SteamCmdRetryCredential {
	return (& $script:steamCmdRetryCredentialResolver)
}

function Set-SteamCmdRetryCredentialResolver {
	param([scriptblock] $Resolver)

	if ($Resolver)
		{
			$script:steamCmdRetryCredentialResolver = $Resolver
		} else {
			$script:steamCmdRetryCredentialResolver = { Request-SteamCmdRetryCredential }
		}
}

function Get-SavedSteamCmdCredential {
	$state = Get-StateConfig
	if (!$state -or !($state.PSObject.Properties.Name -contains 'serverSteamAuth') -or !$state.serverSteamAuth)
		{
			return $null
		}

	$username = Unprotect-StateSecret $state.serverSteamAuth.usernameBlob
	$password = Unprotect-StateSecret $state.serverSteamAuth.passwordBlob

	if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password))
		{
			return $null
		}

	$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
	return New-Object System.Management.Automation.PSCredential ($username, $securePassword)
}

function Clear-SteamCmdCredential {
	$state = Get-StateConfig
	$cleared = ($null -ne (Get-SteamCmdSessionCredential))
	$hadFailureMarker = Test-SteamCmdLastSignInFailed

	Clear-SteamCmdSessionCredential

	if ($state -and ($state.PSObject.Properties.Name -contains 'serverSteamAuth'))
		{
			$state.PSObject.Properties.Remove('serverSteamAuth')
			Save-StateConfig $state
			$cleared = $true
		}
	Clear-SteamCmdLastSignInFailed
	if ($hadFailureMarker)
		{
			$cleared = $true
		}

	return $cleared
}

function Prompt-SteamCmdCredential {
	param(
		[bool] $Persist = $true,
		[switch] $PendingSave
	)

	Write-Host "Steam account setup"
	Write-Host "-------------------"
	Write-Host "Use a Steam account that owns DayZ."
	if ($PendingSave)
		{
			Write-Host "These credentials will replace your saved login after a successful sign-in."
		} elseif ($Persist) {
			Write-Host "These credentials are stored encrypted for the current Windows user."
		} else {
			Write-Host "These credentials are used for this session only."
		}
	Write-Host "If Steam Guard prompts you, approve the sign-in in the Steam app."
	Write-Host "If Steam Guard uses email, SteamCMD will ask for the code in this same window after you enter your password."
	Write-Host ""

	$username = Read-Host -Prompt 'Steam account name'
	if ([string]::IsNullOrWhiteSpace($username))
		{
			Write-Host "No Steam account name was entered."
			Write-Host ""
			return $null
		}

	$securePasswordInput = Read-Host -Prompt 'Steam password' -AsSecureString
	if ($securePasswordInput -is [System.Security.SecureString])
		{
			$securePassword = $securePasswordInput
			$password = (New-Object System.Management.Automation.PSCredential ('steam', $securePassword)).GetNetworkCredential().Password
		} else {
			$password = [string] $securePasswordInput
			if (![string]::IsNullOrWhiteSpace($password))
				{
					$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
				}
		}
	if ([string]::IsNullOrWhiteSpace($password))
		{
			Write-Host "No Steam password was entered."
			Write-Host ""
			return $null
		}

	$credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
	if ($PendingSave)
		{
			# Defer the disk write to the caller - they will only save once
			# the new credentials have actually authenticated successfully.
			Set-SteamCmdSessionCredential $credential
			Write-Host "New Steam credentials entered. They will be saved if sign-in succeeds."
		} elseif ($Persist) {
			# Clear any leftover one-time session credential so the status
			# helper reports 'Saved' (not 'Session only') after this call -
			# the saved copy will be loaded fresh from disk on demand.
			Clear-SteamCmdSessionCredential
			Save-SteamCmdCredential $credential
			Write-Host "Saved encrypted Steam credentials for future downloads."
		} else {
			Set-SteamCmdSessionCredential $credential
			Write-Host "Using Steam credentials for this session only."
		}

	Write-Host ""

	return $credential
}

function Ensure-SteamCmdCredential {
	return (Get-SavedSteamCmdCredential)
}

function Test-SteamCmdLastSignInFailed {
	$state = Get-StateConfig
	if (!$state -or !($state.PSObject.Properties.Name -contains 'lastSteamCmdSignInFailed'))
		{
			return $false
		}

	return [bool] $state.lastSteamCmdSignInFailed
}

function Set-SteamCmdLastSignInFailed {
	param([bool] $Failed = $true)

	$state = Get-StateConfig
	if ($state.PSObject.Properties.Name -contains 'lastSteamCmdSignInFailed')
		{
			$state.lastSteamCmdSignInFailed = $Failed
		} else {
			$state | Add-Member -NotePropertyName lastSteamCmdSignInFailed -NotePropertyValue $Failed -Force
		}

	Save-StateConfig $state
}

function Clear-SteamCmdLastSignInFailed {
	Set-SteamCmdLastSignInFailed -Failed:$false
}

function Get-SteamCmdCredentialStatus {
	if (Test-SteamCmdLastSignInFailed)
		{
			return 'Last sign-in failed'
		}

	if (Get-SteamCmdSessionCredential)
		{
			return 'Session only'
		}

	if (Get-SavedSteamCmdCredential)
		{
			return 'Saved'
		}

	return 'Not configured'
}

function Get-ActiveSteamCmdCredential {
	$sessionCredential = Get-SteamCmdSessionCredential
	if ($sessionCredential)
		{
			return $sessionCredential
		}

	return (Get-SavedSteamCmdCredential)
}

function Request-SteamCmdDownloadCredential {
	Write-Host "SteamCMD account required"
	Write-Host "-------------------------"
	Write-Host "Choose how to use your Steam account for this download."
	Write-Host "1) Use account once"
	Write-Host "2) Save account securely"
	Write-Host "3) Cancel"
	Write-Host ""

	while ($true)
		{
			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					'1' { return (Prompt-SteamCmdCredential -Persist:$false) }
					'2' { return (Prompt-SteamCmdCredential -Persist:$true) }
					'3' {
						Write-Host "Download was canceled."
						Write-Host ""
						return $null
					}
					default {
						Write-Host "Select a number from the list (1-3)."
						Write-Host ""
					}
				}
		}
}

function Resolve-SteamCmdDownloadCredential {
	$credential = Get-ActiveSteamCmdCredential
	if ($credential)
		{
			return $credential
		}

	return (Request-SteamCmdDownloadCredential)
}

function Test-SteamCmdCredentialConfigured {
	return ($null -ne (Get-SavedSteamCmdCredential))
}

function Get-ConfiguredWorkshopIds {
	param(
		$Config,
		[string] $Kind
	)

	if (!$Config)
		{
			return @()
		}

	$pythonResult = Invoke-HybridJsonCommandFromConfig $Config @('configured-ids-json', '--platform', 'windows', '--kind', $Kind)
	if ($null -ne $pythonResult)
		{
			return @($pythonResult | ForEach-Object { [string] $_ })
		}

	if (!$Config.$Kind)
		{
			return @()
		}

	$validated = Get-ValidatedWorkshopIdSet @($Config.$Kind)
	return @($validated.Valid)
}

function Get-ActiveWorkshopIdsFromConfig {
	param(
		$Config,
		[ValidateSet('mods','serverMods')]
		[string] $Kind
	)

	if (!$Config)
		{
			return @()
		}

	$pythonResult = Invoke-HybridJsonCommandFromConfig $Config @('active-ids-json', '--platform', 'windows', '--kind', $Kind, '--strict-active-group')
	if ($null -ne $pythonResult)
		{
			return @($pythonResult | ForEach-Object { [string] $_ })
		}

	$activeName = if ($Config.PSObject.Properties.Name -contains 'activeGroup') { [string] $Config.activeGroup } else { '' }
	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }

	if ([string]::IsNullOrWhiteSpace($activeName))
		{
			return @()
		}

	$group = Get-ModGroupByName $groups $activeName
	if (!$group)
		{
			return @()
		}

	if ($Kind -eq 'serverMods')
		{
			return @(if ($group.serverMods) { @($group.serverMods | Where-Object { $_ }) } else { @() })
		}

	return @(if ($group.mods) { @($group.mods | Where-Object { $_ }) } else { @() })
}

function Get-GroupStatusSummaryFromConfig {
	param($Config)

	if (!$Config)
		{
			return $null
		}

	$pythonResult = Invoke-HybridJsonCommandFromConfig $Config @('group-status-json', '--platform', 'windows')
	if ($null -ne $pythonResult)
		{
			return $pythonResult
		}

	$activeName = if ($Config.PSObject.Properties.Name -contains 'activeGroup') { [string] $Config.activeGroup } else { '' }
	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }

	if ([string]::IsNullOrWhiteSpace($activeName))
		{
			return [pscustomobject]@{
				activeGroup   = ''
				groupState    = 'none'
				clientCount   = 0
				serverCount   = 0
				danglingCount = 0
				missionName   = ''
			}
		}

	$group = Get-ModGroupByName $groups $activeName
	if (!$group)
		{
			return [pscustomobject]@{
				activeGroup   = $activeName
				groupState    = 'missing'
				clientCount   = 0
				serverCount   = 0
				danglingCount = 0
				missionName   = ''
			}
		}

	$resolved = Resolve-ModGroupAgainstLibrary $Config $group
	return [pscustomobject]@{
		activeGroup   = $activeName
		groupState    = 'present'
		clientCount   = @($group.mods).Count
		serverCount   = @($group.serverMods).Count
		danglingCount = @($resolved.DanglingMods).Count + @($resolved.DanglingServerMods).Count
		missionName   = if ($group.PSObject.Properties.Name -contains 'mission') { [string] $group.mission } else { '' }
	}
}

function Get-GroupCatalogSummaryFromConfig {
	param($Config)

	if (!$Config)
		{
			return $null
		}

	$pythonResult = Invoke-HybridJsonCommandFromConfig $Config @('group-catalog-json', '--platform', 'windows')
	if ($null -ne $pythonResult)
		{
			return $pythonResult
		}

	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }
	return [pscustomobject]@{
		activeGroup      = if ($Config.PSObject.Properties.Name -contains 'activeGroup') { [string] $Config.activeGroup } else { '' }
		libraryClientIds = @(Get-ConfiguredWorkshopIds $Config 'mods')
		libraryServerIds = @(Get-ConfiguredWorkshopIds $Config 'serverMods')
		groups           = @(
			foreach ($group in $groups)
				{
					[pscustomobject]@{
						name           = [string] $group.name
						modCount       = @($group.mods).Count
						serverModCount = @($group.serverMods).Count
						missionName    = if ($group.PSObject.Properties.Name -contains 'mission') { [string] $group.mission } else { '' }
					}
				}
		)
	}
}

function Get-GroupDetailFromConfig {
	param(
		$Config,
		[string] $GroupName
	)

	if (!$Config -or [string]::IsNullOrWhiteSpace($GroupName))
		{
			return $null
		}

	$detail = Invoke-HybridJsonCommandFromConfig $Config @('group-detail-json', '--platform', 'windows', '--group-name', $GroupName)
	if ($null -ne $detail)
		{
			return [pscustomobject]@{
				GroupName          = [string] $detail.groupName
				MissionName        = [string] $detail.missionName
				ResolvedMods       = @($detail.resolvedMods)
				DanglingMods       = @($detail.danglingMods | ForEach-Object { [string] $_ })
				ResolvedServerMods = @($detail.resolvedServerMods)
				DanglingServerMods = @($detail.danglingServerMods | ForEach-Object { [string] $_ })
			}
		}

	return $null
}

function Get-WorkshopUsageFromConfig {
	param(
		$Config,
		[string] $WorkshopId,
		[ValidateSet('mods','serverMods')]
		[string] $Kind
	)

	if (!$Config -or [string]::IsNullOrWhiteSpace($WorkshopId))
		{
			return $null
		}

	return (Invoke-HybridJsonCommandFromConfig $Config @('workshop-usage-json', '--platform', 'windows', '--workshop-id', $WorkshopId, '--kind', $Kind))
}

function Invoke-HybridGroupMutationFromConfig {
	param(
		$Config,
		[ValidateSet('set-active','rename','delete','upsert')]
		[string] $Operation,
		[string] $GroupName = $null,
		[string] $OldName = $null,
		[string] $NewName = $null,
		[string] $ExistingName = $null,
		[string[]] $ClientIds = @(),
		[string[]] $ServerIds = @(),
		[string] $MissionName = $null
	)

	if (!$Config)
		{
			return $null
		}

	$pythonArgs = @('mutate-groups-json', '--platform', 'windows', '--operation', $Operation)
	if ($null -ne $GroupName) { $pythonArgs += @('--group-name', $GroupName) }
	if ($null -ne $OldName) { $pythonArgs += @('--old-name', $OldName) }
	if ($null -ne $NewName) { $pythonArgs += @('--new-name', $NewName) }
	if ($null -ne $ExistingName) { $pythonArgs += @('--existing-name', $ExistingName) }
	if ($ClientIds.Count -gt 0) { $pythonArgs += @('--client-ids-json', (ConvertTo-Json -InputObject @($ClientIds) -Compress)) }
	if ($ServerIds.Count -gt 0) { $pythonArgs += @('--server-ids-json', (ConvertTo-Json -InputObject @($ServerIds) -Compress)) }
	if ($null -ne $MissionName) { $pythonArgs += @('--mission-name', $MissionName) }
	return (Invoke-HybridJsonCommandFromConfig $Config $pythonArgs)
}

function Invoke-HybridRemoveWorkshopIdFromConfig {
	param(
		$Config,
		[string] $WorkshopId
	)

	if (!$Config -or [string]::IsNullOrWhiteSpace($WorkshopId))
		{
			return $null
		}

	return (Invoke-HybridJsonCommandFromConfig $Config @('remove-workshop-id-json', '--platform', 'windows', '--workshop-id', $WorkshopId))
}

function Invoke-HybridInventoryMutationFromConfig {
	param(
		$Config,
		[ValidateSet('add-workshop-item','move-workshop-item')]
		[string] $Operation,
		[ValidateSet('mods','serverMods')]
		[string] $TargetKind,
		[string] $WorkshopId,
		[string] $ItemName = $null,
		[string] $ItemUrl = $null
	)

	if (!$Config -or [string]::IsNullOrWhiteSpace($WorkshopId))
		{
			return $null
		}

	$pythonArgs = @(
		'mutate-inventory-json',
		'--platform', 'windows',
		'--operation', $Operation,
		'--target-kind', $TargetKind,
		'--workshop-id', $WorkshopId
	)
	if ($null -ne $ItemName) { $pythonArgs += @('--item-name', $ItemName) }
	if ($null -ne $ItemUrl) { $pythonArgs += @('--item-url', $ItemUrl) }
	return (Invoke-HybridJsonCommandFromConfig $Config $pythonArgs)
}

function Invoke-HybridGroupUpsertFromConfig {
	param(
		$Config,
		[string] $GroupName,
		[string[]] $ClientIds = @(),
		[string[]] $ServerIds = @(),
		[string] $MissionName = $null,
		[string] $ExistingName = $null
	)

	return Invoke-HybridGroupMutationFromConfig `
		-Config $Config `
		-Operation 'upsert' `
		-GroupName $GroupName `
		-ExistingName $ExistingName `
		-ClientIds @($ClientIds) `
		-ServerIds @($ServerIds) `
		-MissionName $MissionName
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

function Get-MissionFolderFromServerConfigText {
	param([string] $Text)

	if ([string]::IsNullOrWhiteSpace($Text))
		{
			return $null
		}

	$match = [regex]::Match($Text, 'template\s*=\s*"([^"]+)"', 'IgnoreCase')

	if (!$match.Success)
		{
			return $null
		}

	return $match.Groups[1].Value
}

function Set-MissionFolderInServerConfigText {
	param([string] $Text, [string] $Mission)

	if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Mission))
		{
			return $Text
		}

	$pattern = 'template\s*=\s*"([^"]+)"'

	if ($Text -notmatch $pattern)
		{
			return $Text
		}

	return [regex]::Replace($Text, $pattern, "template=`"$Mission`"", 'IgnoreCase')
}

function Resolve-ServerFolderForMissions {
	param($Config)

	if ($Config -is [hashtable] -and $Config.ContainsKey('serverFolder') -and -not [string]::IsNullOrWhiteSpace($Config.serverFolder))
		{
			return $Config.serverFolder
		}

	if ($Config -and ($Config.PSObject.Properties.Name -contains 'serverFolder') -and -not [string]::IsNullOrWhiteSpace($Config.serverFolder))
		{
			return $Config.serverFolder
		}

	return Get-CurrentServerDirectory
}

function Get-MissionFolderOptions {
	param([string] $ServerFolder)
	if ([string]::IsNullOrWhiteSpace($ServerFolder)) { return @() }
	$mp = Join-Path $ServerFolder 'mpmissions'
	if (-not (Test-Path -LiteralPath $mp)) { return @() }
	return @(Get-ChildItem -LiteralPath $mp -Directory | Select-Object -ExpandProperty Name)
}

function Select-MissionFromList {
	param([string] $ServerFolder, [string] $Prompt)
	$options = Get-MissionFolderOptions $ServerFolder
	if (@($options).Count -eq 0)
		{
			return (Read-Host -Prompt "$Prompt (enter folder name)")
		}

	Write-Host ""
	Write-Host " Missions:"
	Write-Host " $([string]::new([char]0x2500, 37))"
	for ($i = 0; $i -lt $options.Count; $i++)
		{
			Write-Host "  $($i + 1)) $($options[$i])"
		}
	Write-Host ""

	$raw = Read-Host -Prompt "$Prompt (0 to enter manually)"
	if ($raw -eq '0') { return (Read-Host -Prompt 'Enter mission folder name') }

	$idx = 0
	if (-not [int]::TryParse($raw, [ref] $idx) -or $idx -lt 1 -or $idx -gt $options.Count) { return $null }

	return $options[$idx - 1]
}

function ConvertTo-ModLaunchString {
	param([string[]] $WorkshopIds)

	$normalizedIds = @($WorkshopIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | ForEach-Object { [string] $_ })

	$pythonArgs = @('launch-string') + $normalizedIds
	$pythonResult = Invoke-HybridPythonCore $pythonArgs
	if ($null -ne $pythonResult)
		{
			return $pythonResult
		}

	if (!$normalizedIds -or ($normalizedIds.Count -eq 0))
		{
			return ''
		}

	return (($normalizedIds | ForEach-Object { "$_;" }) -join '')
}

function Get-ModIdsFromLaunchParameters {
	param(
		[string] $Parameters,
		[string] $Kind
	)

	$pythonArgs = @('get-mod-ids', '--kind', $Kind, '--parameters', $Parameters)
	$pythonResult = Invoke-HybridPythonCore $pythonArgs
	if ($null -ne $pythonResult)
		{
			try
				{
					return @((ConvertFrom-Json $pythonResult) | ForEach-Object { [string] $_ })
				}
			catch
				{
				}
		}

	if ([string]::IsNullOrWhiteSpace($Parameters))
		{
			return @()
		}

	$flag = if ($Kind -eq 'serverMods') { 'serverMod' } else { 'mod' }

	# Match quoted form: "-mod=IDs" or unquoted: -mod=IDs
	$pattern = '"?-' + $flag + '=([^"]*)"?'
	$match = [regex]::Match($Parameters, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

	if (!$match.Success)
		{
			return @()
		}

	$raw = $match.Groups[1].Value
	$ids = @($raw -split ';' | Where-Object { $_ -match '^\d{8,}$' })
	return $ids
}

function Add-ModToLaunchParameters {
	param(
		[string] $Parameters,
		[string] $Kind,
		[string] $WorkshopId
	)

	if ([string]::IsNullOrWhiteSpace($Parameters))
		{
			return $Parameters
		}

	$flag = if ($Kind -eq 'serverMods') { 'serverMod' } else { 'mod' }
	$existingIds = Get-ModIdsFromLaunchParameters $Parameters $Kind

	if ($existingIds -contains $WorkshopId)
		{
			return $Parameters
		}

	# Check if the flag section exists
	$pattern = '("?)-' + $flag + '=([^"]*)("?)'
	$match = [regex]::Match($Parameters, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

	if ($match.Success)
		{
			$openQuote = $match.Groups[1].Value
			$idsSection = $match.Groups[2].Value
			$closeQuote = $match.Groups[3].Value

			# Append new ID with trailing semicolon
			$newSection = $idsSection.TrimEnd(';')
			if ($newSection.Length -gt 0) { $newSection += ';' }
			$newSection += "$WorkshopId;"

			$replacement = "$openQuote-$flag=$newSection$closeQuote"
			$result = $Parameters.Substring(0, $match.Index) + $replacement + $Parameters.Substring($match.Index + $match.Length)
			return $result
		}

	# Flag section not found; do not insert one automatically
	return $Parameters
}

function Remove-ModFromLaunchParameters {
	param(
		[string] $Parameters,
		[string] $WorkshopId
	)

	if ([string]::IsNullOrWhiteSpace($Parameters))
		{
			return $Parameters
		}

	foreach ($flag in @('mod', 'serverMod'))
		{
			$pattern = '("?)-' + $flag + '=([^"]*)("?)'
			$match = [regex]::Match($Parameters, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

			if (!$match.Success) { continue }

			$openQuote = $match.Groups[1].Value
			$idsSection = $match.Groups[2].Value
			$closeQuote = $match.Groups[3].Value

			$ids = @($idsSection -split ';' | Where-Object { $_ -match '^\d{8,}$' -and $_ -ne $WorkshopId })
			$newIds = if ($ids.Count -gt 0) { ($ids -join ';') + ';' } else { '' }

			$replacement = "$openQuote-$flag=$newIds$closeQuote"
			$Parameters = $Parameters.Substring(0, $match.Index) + $replacement + $Parameters.Substring($match.Index + $match.Length)
		}

	return $Parameters
}

function Set-ModsInLaunchParameters {
	param(
		[string] $Parameters,
		[string] $Kind,
		[string[]] $WorkshopIds
	)

	$normalizedIds = @($WorkshopIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | ForEach-Object { [string] $_ })

	$pythonArgs = @('set-mods', '--kind', $Kind, '--parameters', $Parameters) + $normalizedIds
	$pythonResult = Invoke-HybridPythonCore $pythonArgs
	if ($null -ne $pythonResult)
		{
			return $pythonResult
		}

	if ([string]::IsNullOrWhiteSpace($Parameters))
		{
			return $Parameters
		}

	$flag = if ($Kind -eq 'serverMods') { 'serverMod' } else { 'mod' }
	$pattern = '("?)-' + $flag + '=([^"]*)("?)'
	$match = [regex]::Match($Parameters, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

	if (!$match.Success)
		{
			return $Parameters
		}

	$openQuote = $match.Groups[1].Value
	$closeQuote = $match.Groups[3].Value

	$newIds = if ($normalizedIds -and $normalizedIds.Count -gt 0) { ($normalizedIds -join ';') + ';' } else { '' }
	$replacement = "$openQuote-$flag=$newIds$closeQuote"
	$result = $Parameters.Substring(0, $match.Index) + $replacement + $Parameters.Substring($match.Index + $match.Length)
	return $result
}

function New-DefaultModGroup {
	param(
		[string] $Name,
		[string[]] $Mods = @(),
		[string[]] $ServerMods = @()
	)

	$normalizedMods = @($Mods | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) })
	$normalizedServerMods = @($ServerMods | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) })

	return [pscustomobject]@{
		name       = $Name
		mods       = @($normalizedMods)
		serverMods = @($normalizedServerMods)
	}
}

function Test-ModGroupNameValid {
	param(
		[string] $Name,
		$ExistingGroups,
		[string] $IgnoreName = $null
	)

	if ([string]::IsNullOrWhiteSpace($Name))
		{
			return $false
		}

	if ($Name.Length -gt 64)
		{
			return $false
		}

	$lower = $Name.ToLowerInvariant()
	$ignoreLower = if ($IgnoreName) { $IgnoreName.ToLowerInvariant() } else { $null }

	foreach ($group in @($ExistingGroups))
		{
			if (!$group -or !$group.name) { continue }
			$existingLower = ([string] $group.name).ToLowerInvariant()
			if ($ignoreLower -and $existingLower -eq $ignoreLower) { continue }
			if ($existingLower -eq $lower) { return $false }
		}

	return $true
}

function Get-ModGroupByName {
	param(
		$Groups,
		[string] $Name
	)

	if (!$Groups -or [string]::IsNullOrWhiteSpace($Name))
		{
			return $null
		}

	$lower = $Name.ToLowerInvariant()
	foreach ($group in @($Groups))
		{
			if (!$group -or !$group.name) { continue }
			if (([string] $group.name).ToLowerInvariant() -eq $lower)
				{
					return $group
				}
		}

	return $null
}

function Resolve-ModGroupAgainstLibrary {
	param(
		$Config,
		$Group
	)

	$libraryMods = if ($Config -and $Config.mods) { @($Config.mods | Where-Object { $_ -and $_.workshopId }) } else { @() }
	$libraryServerMods = if ($Config -and $Config.serverMods) { @($Config.serverMods | Where-Object { $_ -and $_.workshopId }) } else { @() }

	$groupModIds = if ($Group -and $Group.mods) { @($Group.mods | Where-Object { $_ }) } else { @() }
	$groupServerModIds = if ($Group -and $Group.serverMods) { @($Group.serverMods | Where-Object { $_ }) } else { @() }

	$resolvedMods = @()
	$danglingMods = @()
	foreach ($id in $groupModIds)
		{
			$match = $libraryMods | Where-Object { $_.workshopId -eq $id } | Select-Object -First 1
			if ($match) { $resolvedMods += $match } else { $danglingMods += $id }
		}

	$resolvedServerMods = @()
	$danglingServerMods = @()
	foreach ($id in $groupServerModIds)
		{
			$match = $libraryServerMods | Where-Object { $_.workshopId -eq $id } | Select-Object -First 1
			if ($match) { $resolvedServerMods += $match } else { $danglingServerMods += $id }
		}

	return [pscustomobject]@{
		ResolvedMods       = $resolvedMods
		DanglingMods       = $danglingMods
		ResolvedServerMods = $resolvedServerMods
		DanglingServerMods = $danglingServerMods
	}
}

function Get-GroupsReferencingMod {
	param(
		$Groups,
		[string] $WorkshopId,
		[ValidateSet('mods','serverMods')]
		[string] $Kind
	)

	$result = @()
	foreach ($group in @($Groups))
		{
			if (!$group) { continue }
			$ids = if ($group.$Kind) { @($group.$Kind) } else { @() }
			if ($ids -contains $WorkshopId)
				{
					$result += $group
				}
		}

	return $result
}

function Sync-LaunchParametersFromActiveGroup {
	param($Config)

	if (!$Config) { return }
	if (-not ($Config.PSObject.Properties.Name -contains 'launchParameters')) { return }
	if ([string]::IsNullOrWhiteSpace($Config.launchParameters)) { return }

	$modIds = Get-ActiveWorkshopIdsFromConfig $Config 'mods'
	$serverModIds = Get-ActiveWorkshopIdsFromConfig $Config 'serverMods'
	$updated = $Config.launchParameters
	$updated = [regex]::Replace($updated, '\s*"?-mod=[^"\s]*"?', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$updated = [regex]::Replace($updated, '\s*"?-serverMod=[^"\s]*"?', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$updated = ($updated -replace '\s+', ' ').Trim()

	$modLaunch = ConvertTo-ModLaunchString $modIds
	$serverModLaunch = ConvertTo-ModLaunchString $serverModIds

	if (-not [string]::IsNullOrWhiteSpace($updated))
		{
			$updated += ' '
		}

	$updated += '"-mod=' + $modLaunch + '"'
	$updated += ' "-serverMod=' + $serverModLaunch + '"'
	$Config.launchParameters = $updated.Trim()
}

function Sync-ServerConfigMission {
	param($Config, [string] $Mission)

	if (!$Config -or [string]::IsNullOrWhiteSpace($Mission)) { return $false }
	$serverFolder = Resolve-ServerFolderForMissions $Config
	if ([string]::IsNullOrWhiteSpace($serverFolder)) { return $false }
	$cfgPath = Join-Path $serverFolder 'serverDZ.cfg'
	if (-not (Test-Path -LiteralPath $cfgPath)) { return $false }
	$text = Get-Content -LiteralPath $cfgPath -Raw
	$updated = Set-MissionFolderInServerConfigText $text $Mission
	if ($updated -ne $text) { Set-Content -LiteralPath $cfgPath -Value $updated }
	return $true
}

function Set-ActiveModGroup {
	param(
		$Config,
		[string] $GroupName
	)

	if (!$Config) { return $null }

	$updatedConfig = Invoke-HybridGroupMutationFromConfig -Config $Config -Operation 'set-active' -GroupName $GroupName
	if ($updatedConfig)
		{
			Sync-LaunchParametersFromActiveGroup $updatedConfig
			$groups = if ($updatedConfig.PSObject.Properties.Name -contains 'modGroups') { @($updatedConfig.modGroups) } else { @() }
			$target = Get-ModGroupByName $groups $updatedConfig.activeGroup
			if ($target -and $target.PSObject.Properties.Name -contains 'mission' -and -not [string]::IsNullOrWhiteSpace($target.mission))
				{
					Sync-ServerConfigMission $updatedConfig $target.mission
				}
			return $updatedConfig
		}

	if ([string]::IsNullOrWhiteSpace($GroupName))
		{
			if (-not ($Config.PSObject.Properties.Name -contains 'activeGroup'))
				{
					$Config | Add-Member -NotePropertyName activeGroup -NotePropertyValue '' -Force
				}
			else
				{
					$Config.activeGroup = ''
				}

			Sync-LaunchParametersFromActiveGroup $Config
			return $Config
		}

	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }
	$target = Get-ModGroupByName $groups $GroupName
	if (!$target) { return $null }

	if (-not ($Config.PSObject.Properties.Name -contains 'activeGroup'))
		{
			$Config | Add-Member -NotePropertyName activeGroup -NotePropertyValue $target.name -Force
		}
	else
		{
			$Config.activeGroup = $target.name
		}

	Sync-LaunchParametersFromActiveGroup $Config
	if ($target.PSObject.Properties.Name -contains 'mission' -and -not [string]::IsNullOrWhiteSpace($target.mission))
		{
			Sync-ServerConfigMission $Config $target.mission
		}
	return $Config
}

function Rename-ModGroup {
	param(
		$Config,
		[string] $OldName,
		[string] $NewName
	)

	if (!$Config) { return $null }

	$updatedConfig = Invoke-HybridGroupMutationFromConfig -Config $Config -Operation 'rename' -OldName $OldName -NewName $NewName
	if ($updatedConfig)
		{
			return $updatedConfig
		}
	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }
	$target = Get-ModGroupByName $groups $OldName
	if (!$target) { return $null }

	if (-not (Test-ModGroupNameValid $NewName $groups -IgnoreName $OldName)) { return $null }

	$target.name = $NewName.Trim()
	if ($Config.activeGroup -eq $OldName)
		{
			$Config.activeGroup = $target.name
		}
	return $Config
}

function Remove-ModGroup {
	param(
		$Config,
		[string] $Name
	)

	if (!$Config) { return $null }

	$updatedConfig = Invoke-HybridGroupMutationFromConfig -Config $Config -Operation 'delete' -GroupName $Name
	if ($updatedConfig)
		{
			return $updatedConfig
		}
	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }
	if (@($groups).Count -le 1) { return $null }
	if ($Config.activeGroup -eq $Name) { return $null }

	$target = Get-ModGroupByName $groups $Name
	if (!$target) { return $null }

	$Config.modGroups = @($groups | Where-Object { $_.name -ne $target.name })
	return $Config
}

function Remove-ModFromAllGroups {
	param(
		$Config,
		[string] $WorkshopId,
		[ValidateSet('mods','serverMods')]
		[string] $Kind
	)

	if (!$Config) { return }
	$groups = if ($Config.PSObject.Properties.Name -contains 'modGroups') { @($Config.modGroups) } else { @() }

	$affectedActive = $false
	foreach ($group in $groups)
		{
			$ids = if ($group.$Kind) { @($group.$Kind) } else { @() }
			if ($ids -contains $WorkshopId)
				{
					$group.$Kind = @($ids | Where-Object { $_ -ne $WorkshopId })
					if ($Config.activeGroup -eq $group.name) { $affectedActive = $true }
				}
		}

	if ($affectedActive)
		{
			Sync-LaunchParametersFromActiveGroup $Config
		}
}

function ConvertFrom-ChecklistInput {
	param(
		[string] $InputText,
		[int] $MaxIndex
	)

	if ([string]::IsNullOrWhiteSpace($InputText)) { return @() }

	$result = @()
	$tokens = $InputText -split '[,\s]+' | Where-Object { $_ }
	foreach ($token in $tokens)
		{
			if ($token -match '^\s*(\d+)\s*-\s*(\d+)\s*$')
				{
					$a = [int] $Matches[1]
					$b = [int] $Matches[2]
					if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
					for ($i = $a; $i -le $b; $i++)
						{
							if ($i -ge 1 -and $i -le $MaxIndex -and ($result -notcontains $i))
								{
									$result += $i
								}
						}
				}
			elseif ($token -match '^\d+$')
				{
					$n = [int] $token
					if ($n -ge 1 -and $n -le $MaxIndex -and ($result -notcontains $n))
						{
							$result += $n
						}
				}
		}

	return $result
}

function Invoke-ModGroupChecklistEditor {
	param(
		$Config,
		$Group
	)

	$libraryMods = if ($Config.mods) { @($Config.mods | Where-Object { $_ -and $_.workshopId }) } else { @() }
	$libraryServerMods = if ($Config.serverMods) { @($Config.serverMods | Where-Object { $_ -and $_.workshopId }) } else { @() }

	$selectedMods = @{}
	$selectedServerMods = @{}
	foreach ($id in @($Group.mods)) { if ($id) { $selectedMods[$id] = $true } }
	foreach ($id in @($Group.serverMods)) { if ($id) { $selectedServerMods[$id] = $true } }

	while ($true)
		{
			Clear-MenuScreen
			Write-Host ""
			Write-Host "Editing group: $($Group.name)"
			Write-Host ""
			Write-Host "After saving, you'll choose the map/mission for this group."
			Write-Host ""

			$rowIndex = 0
			$rowKinds = @()
			$rowIds = @()

			Write-Host "MODS"
			foreach ($mod in $libraryMods)
				{
					$rowIndex++
					$rowKinds += 'mods'
					$rowIds += $mod.workshopId
					$name = if ([string]::IsNullOrWhiteSpace($mod.name)) { '(unnamed)' } else { $mod.name }
					$mark = if ($selectedMods.ContainsKey($mod.workshopId)) { 'x' } else { ' ' }
					$pad = $name.PadRight(30)
					Write-Host ("  [{0}] {1,3}. {2} ({3})" -f $mark, $rowIndex, $pad, $mod.workshopId)
				}

			Write-Host ""
			Write-Host "SERVER MODS"
			foreach ($mod in $libraryServerMods)
				{
					$rowIndex++
					$rowKinds += 'serverMods'
					$rowIds += $mod.workshopId
					$name = if ([string]::IsNullOrWhiteSpace($mod.name)) { '(unnamed)' } else { $mod.name }
					$mark = if ($selectedServerMods.ContainsKey($mod.workshopId)) { 'x' } else { ' ' }
					$pad = $name.PadRight(30)
					Write-Host ("  [{0}] {1,3}. {2} ({3})" -f $mark, $rowIndex, $pad, $mod.workshopId)
				}

			$danglingMods = @()
			foreach ($id in @($selectedMods.Keys))
				{
					if (-not ($libraryMods | Where-Object { $_.workshopId -eq $id }))
						{
							$danglingMods += $id
						}
				}

			$danglingServerMods = @()
			foreach ($id in @($selectedServerMods.Keys))
				{
					if (-not ($libraryServerMods | Where-Object { $_.workshopId -eq $id }))
						{
							$danglingServerMods += $id
						}
				}

			$danglingRowIds = @()
			$danglingRowKinds = @()
			if (($danglingMods.Count + $danglingServerMods.Count) -gt 0)
				{
					Write-Host ""
					Write-Host "DANGLING (not in library) - use 'd<n>' to remove"
					foreach ($id in $danglingMods)
						{
							$rowIndex++
							$danglingRowIds += $id
							$danglingRowKinds += 'mods'
							Write-Host ("       {0,3}. (mods)       {1}" -f $rowIndex, $id)
						}
					foreach ($id in $danglingServerMods)
						{
							$rowIndex++
							$danglingRowIds += $id
							$danglingRowKinds += 'serverMods'
							Write-Host ("       {0,3}. (serverMods) {1}" -f $rowIndex, $id)
						}
				}

			$firstDangling = $rowKinds.Count + 1

			Write-Host ""
			Write-Host "Commands:"
			Write-Host "  <numbers>   toggle (e.g. '1' or '1,3,5' or '1-4')"
			Write-Host "  a           check all      n   uncheck all"
			Write-Host "  s           save and exit  c   cancel (discard changes)"
			Write-Host ""

			$cmd = Read-Host -Prompt 'Command'
			if ($null -eq $cmd) { $cmd = '' }
			$cmd = $cmd.Trim()

			if ($cmd -eq 's')
				{
					$savedMods = @(@($libraryMods | Where-Object { $selectedMods.ContainsKey($_.workshopId) } | ForEach-Object { $_.workshopId }) + @($danglingMods))
					$savedServerMods = @(@($libraryServerMods | Where-Object { $selectedServerMods.ContainsKey($_.workshopId) } | ForEach-Object { $_.workshopId }) + @($danglingServerMods))
					return [pscustomobject]@{
						Saved      = $true
						Mods       = $savedMods
						ServerMods = $savedServerMods
					}
				}
			elseif ($cmd -eq 'c')
				{
					return [pscustomobject]@{ Saved = $false }
				}
			elseif ($cmd -eq 'a')
				{
					foreach ($m in $libraryMods) { $selectedMods[$m.workshopId] = $true }
					foreach ($m in $libraryServerMods) { $selectedServerMods[$m.workshopId] = $true }
				}
			elseif ($cmd -eq 'n')
				{
					$selectedMods = @{}
					$selectedServerMods = @{}
				}
			elseif ($cmd -match '^d\s*(\d+)$')
				{
					$dIndex = [int] $Matches[1]
					$offset = $dIndex - $firstDangling
					if ($offset -ge 0 -and $offset -lt $danglingRowIds.Count)
						{
							$id = $danglingRowIds[$offset]
							$kind = $danglingRowKinds[$offset]
							if ($kind -eq 'mods')
								{
									$selectedMods.Remove($id) | Out-Null
								}
							else
								{
									$selectedServerMods.Remove($id) | Out-Null
								}
						}
				}
			else
				{
					$selections = ConvertFrom-ChecklistInput $cmd $rowKinds.Count
					foreach ($n in $selections)
						{
							$kind = $rowKinds[$n - 1]
							$id = $rowIds[$n - 1]
							if ($kind -eq 'mods')
								{
									if ($selectedMods.ContainsKey($id)) { $selectedMods.Remove($id) | Out-Null }
									else { $selectedMods[$id] = $true }
								}
							else
								{
									if ($selectedServerMods.ContainsKey($id)) { $selectedServerMods.Remove($id) | Out-Null }
									else { $selectedServerMods[$id] = $true }
								}
						}
				}
		}
}

function Set-GeneratedLaunchMods {
	param(
		[string[]] $Mods,
		[string[]] $ServerMods
	)

	$state = Get-StateConfig
	if (-not ($state.PSObject.Properties.Name -contains 'generatedLaunch') -or -not $state.generatedLaunch)
		{
			$state | Add-Member -NotePropertyName generatedLaunch -NotePropertyValue ([pscustomobject]@{
				mod = ''
				serverMod = ''
			}) -Force
		}
	if ($state.generatedLaunch -and -not ($state.generatedLaunch.PSObject.Properties.Name -contains 'mod'))
		{
			$state.generatedLaunch | Add-Member -NotePropertyName mod -NotePropertyValue '' -Force
		}
	if ($state.generatedLaunch -and -not ($state.generatedLaunch.PSObject.Properties.Name -contains 'serverMod'))
		{
			$state.generatedLaunch | Add-Member -NotePropertyName serverMod -NotePropertyValue '' -Force
		}

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

function Test-SafeServerFolderForRemoval {
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

    return ($fullPath -match '\\steamapps\\common\\')
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

function New-SteamCmdLoginScript {
	param(
		[System.Management.Automation.PSCredential] $Credential,
		[string] $Path
	)

	if (($null -eq $Credential) -or [string]::IsNullOrWhiteSpace($Credential.UserName))
		{
			throw [System.InvalidOperationException] 'Credential is required to create a SteamCMD login script.'
		}

	if ([string]::IsNullOrWhiteSpace($Path))
		{
			$Path = $tempLoginScript
		}

	$parent = Split-Path -Parent $Path
	if (!(Test-Path -LiteralPath $parent))
		{
			New-Item -ItemType Directory -Path $parent -Force >$null
		}

	$password = $Credential.GetNetworkCredential().Password
	@("login $($Credential.UserName) $password") | Set-Content -LiteralPath $Path -Force

	return $Path
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

function Show-ModUpdateSummary {
	param(
		$Config,
		[string[]] $ClientIds,
		[string[]] $ServerIds,
		[object[]] $InvalidClient,
		[object[]] $InvalidServer
	)

	Write-Host ""
	Write-Host "========================================"
	Write-Host " Updating Mods"
	Write-Host "========================================"
	Write-Host ""

	if ($ClientIds.Count -gt 0)
		{
			Write-Host " Client mods ($($ClientIds.Count))"
			Write-Host " $([string]::new([char]0x2500, 37))"
			foreach ($id in $ClientIds)
				{
					$item = @($Config.mods) | Where-Object { $_.workshopId -eq $id } | Select-Object -First 1
					$name = if ($item -and ![string]::IsNullOrWhiteSpace($item.name)) { $item.name } else { '(unnamed)' }
					$paddedName = $name.PadRight(22)
					Write-Host "  $([char]0x00B7) $paddedName ($id)"
				}
			Write-Host ""
		}

	if ($ServerIds.Count -gt 0)
		{
			Write-Host " Server mods ($($ServerIds.Count))"
			Write-Host " $([string]::new([char]0x2500, 37))"
			foreach ($id in $ServerIds)
				{
					$item = @($Config.serverMods) | Where-Object { $_.workshopId -eq $id } | Select-Object -First 1
					$name = if ($item -and ![string]::IsNullOrWhiteSpace($item.name)) { $item.name } else { '(unnamed)' }
					$paddedName = $name.PadRight(22)
					Write-Host "  $([char]0x00B7) $paddedName ($id)"
				}
			Write-Host ""
		}

	$allInvalid = @($InvalidClient) + @($InvalidServer)
	if ($allInvalid.Count -gt 0)
		{
			$invalidList = ($allInvalid | ForEach-Object { [string] $_ }) -join ', '
			Write-Host " Warning: Skipped $($allInvalid.Count) invalid ID(s): $invalidList" -ForegroundColor Yellow
			Write-Host ""
		}
}

function Show-ConfiguredMods {
	param([string] $Kind)

	$config = Get-RootConfig
	$items = @($config.$Kind)

	if ($items.Count -eq 0)
		{
			Write-Host "No mods configured."
			Write-Host ""
			return
		}

	foreach ($item in $items)
		{
			$name = $item.name
			if ([string]::IsNullOrWhiteSpace($name))
				{
					$name = '(no name)'
				}

			$paddedName = $name.PadRight(22)
			Write-Host "  $([char]0x00B7) $paddedName ($($item.workshopId))"
			if (![string]::IsNullOrWhiteSpace($item.url))
				{
					Write-Host "    $($item.url)"
				}
			Write-Host ""
	}
}

function Show-ConfiguredModsMenu {
	param(
		[string] $Kind,
		[string] $Title
	)

	while ($true)
		{
			$config = Get-RootConfig
			$items = if ($config -and $config.$Kind) { @($config.$Kind | Where-Object { $_ }) } else { @() }
			$countLabel = if ($items.Count -gt 0) { " ($($items.Count))" } else { '' }
			Show-MenuHeader "$Title$countLabel"
			Write-Host " $([string]::new([char]0x2500, 37))"
			Show-ConfiguredMods $Kind
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""
			echo " 1) Back"
			echo ""

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

function Prompt-ConfiguredModKind {
	$rawKind = Read-Host -Prompt 'Mod type (client/server)'
	if ([string]::IsNullOrWhiteSpace($rawKind) -or $rawKind -match '^(client|c)$')
		{
			return 'mods'
		}
	if ($rawKind -match '^(server|s)$')
		{
			return 'serverMods'
		}

	Write-Host "Select 'client' or 'server'."
	Write-Host ""
	return $null
}

function Test-SafeLaunchParameters {
    param([string] $Parameters)

    if ([string]::IsNullOrWhiteSpace($Parameters))
        {
            return $true
        }

    # Reject characters that could enable command injection via CreateProcess
    # Allow: alphanumeric, spaces, =, -, _, \, /, ., :, ", ;, @, <, >
    if ($Parameters -match '[&|`$!{}()\[\]]')
        {
            return $false
        }

    return $true
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
	if ($name.Length -gt 100)
		{
			echo "Mod name is too long (maximum 100 characters)."
			echo "`n"
			return
		}
	$url = ''
	if ($rawInput -match '^https?://')
		{
			$url = $rawInput
		} else {
					$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$workshopId"
				}

	$updatedConfig = Invoke-HybridInventoryMutationFromConfig `
		-Config $config `
		-Operation 'add-workshop-item' `
		-TargetKind $Kind `
		-WorkshopId $workshopId `
		-ItemName $name `
		-ItemUrl $url
	if ($updatedConfig)
		{
			$config = $updatedConfig
		}
	else
		{
			Add-WorkshopModToConfig $config $Kind $workshopId $name $url
		}

	# Offer to add to saved launch parameters if they exist
	$launchParams = Get-ConfiguredLaunchParameters $config
	if ($launchParams)
		{
			$addToLaunch = Read-Host -Prompt 'Add this mod to saved launch parameters? (y/n)'
			if ($addToLaunch -eq 'y' -or $addToLaunch -eq 'Y')
				{
					$updatedParams = Add-ModToLaunchParameters $launchParams $Kind $workshopId
					if ($updatedParams -ne $launchParams)
						{
							$config.launchParameters = $updatedParams
							echo "Added to saved launch parameters."
						} else {
							echo "Mod is already in launch parameters or the -$( if ($Kind -eq 'serverMods') { 'serverMod' } else { 'mod' } ) flag was not found."
						}
				}
		}

	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	echo "Added Workshop ID $workshopId."
	echo "`n"
}

function Remove-ConfiguredModFromPrompt {
	$config = Get-RootConfig

	$allMods = @()
	foreach ($item in @($config.mods))
		{
			if ($item -and $item.workshopId)
				{
					$allMods += [pscustomobject]@{ name = $item.name; workshopId = $item.workshopId; kind = 'Client'; configKind = 'mods' }
				}
		}
	foreach ($item in @($config.serverMods))
		{
			if ($item -and $item.workshopId)
				{
					$allMods += [pscustomobject]@{ name = $item.name; workshopId = $item.workshopId; kind = 'Server'; configKind = 'serverMods' }
				}
		}

	if ($allMods.Count -eq 0)
		{
			Write-Host "No mods are configured."
			Write-Host ""
			return
		}

	Write-Host ""
	Write-Host " Configured mods:"
	Write-Host " $([string]::new([char]0x2500, 37))"
	for ($i = 0; $i -lt $allMods.Count; $i++)
		{
			$mod = $allMods[$i]
			$name = if ([string]::IsNullOrWhiteSpace($mod.name)) { '(unnamed)' } else { $mod.name }
			$paddedName = $name.PadRight(22)
			Write-Host "  $($i + 1)) [$($mod.kind)] $paddedName ($($mod.workshopId))"
		}
	Write-Host ""

	$rawInput = Read-Host -Prompt 'Select a mod number to remove (or 0 to cancel)'

	if ($rawInput -eq '0')
		{
			return $false
		}

	$index = 0
	if (-not [int]::TryParse($rawInput, [ref]$index) -or $index -lt 1 -or $index -gt $allMods.Count)
		{
			Write-Host "Invalid selection."
			Write-Host ""
			return
		}

	$selected = $allMods[$index - 1]
	$workshopId = $selected.workshopId
	$configKind = $selected.configKind

	$usageSummary = Get-WorkshopUsageFromConfig $config $workshopId $configKind
	$referencingNames = @()
	$affectedActive = $false
	if ($usageSummary)
		{
			$referencingNames = @($usageSummary.referencingGroups | ForEach-Object { [string] $_ })
			$affectedActive = [bool] $usageSummary.activeGroupAffected
		}
	else
		{
			$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
			$referencing = Get-GroupsReferencingMod $groups $workshopId $configKind
			$referencingNames = @($referencing | ForEach-Object { [string] $_.name })
			$affectedActive = $referencingNames -contains [string] $config.activeGroup
		}
	if (@($referencingNames).Count -gt 0)
		{
			$displayName = if ([string]::IsNullOrWhiteSpace($selected.name)) { $workshopId } else { "$($selected.name) ($workshopId)" }
			Write-Host ""
			Write-Host "Mod '$displayName' is used in $(@($referencingNames).Count) group(s):"
			foreach ($groupName in $referencingNames)
				{
					Write-Host "  - $groupName"
				}
			Write-Host ""
			$confirm = Read-Host -Prompt 'Remove it from these groups and delete? (y/n)'
			if ($confirm -ne 'y' -and $confirm -ne 'Y')
				{
					Write-Host "Cancelled."
					Write-Host ""
					return
				}
		}

	$updatedConfig = Invoke-HybridRemoveWorkshopIdFromConfig $config $workshopId
	if ($updatedConfig)
		{
			$config = $updatedConfig
			if ($affectedActive)
				{
					Sync-LaunchParametersFromActiveGroup $config
				}
		}
	else
		{
			if (@($referencingNames).Count -gt 0)
				{
					Remove-ModFromAllGroups $config $workshopId $configKind
				}
			Remove-WorkshopModFromConfig $config $workshopId
		}

	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	$displayName = if ([string]::IsNullOrWhiteSpace($selected.name)) { $workshopId } else { "$($selected.name) ($workshopId)" }
	Write-Host "Removed $displayName from the configured mod lists."
	Write-Host ""
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
	$targetKind = $null

	if ($target -eq '1')
		{
			$targetKind = 'mods'
		} elseif ($target -eq '2') {
					$targetKind = 'serverMods'
				} else {
							echo "Select a number from the list (1-2)."
							echo "`n"
							return
						}

	$updatedConfig = Invoke-HybridInventoryMutationFromConfig `
		-Config $config `
		-Operation 'move-workshop-item' `
		-TargetKind $targetKind `
		-WorkshopId $workshopId
	if ($updatedConfig)
		{
			$config = $updatedConfig
		}
	else
		{
			Move-WorkshopModInConfig $config $workshopId $targetKind
		}

	Save-RootConfig $config
	Update-GeneratedLaunchFromRootConfig $config

	echo "Moved Workshop ID $workshopId."
	echo "`n"
}

function ModManager_menu {
	while ($true)
		{
			Show-MenuHeader 'Manage Mods'

			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) List client mods"
			echo " 2) List server mods"
			echo " 3) Add mod"
			echo " 4) Remove mod"
			echo " 5) Move mod between client/server"
			echo " 6) Sync/update configured mods now"
			echo " 7) Back to Main Menu"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					1 {
						Show-ConfiguredModsMenu 'mods' 'Client mods'
						continue
					}
					2 {
						Show-ConfiguredModsMenu 'serverMods' 'Server mods'
						continue
					}
					3 {
						$kind = Prompt-ConfiguredModKind
						if (!$kind) { Pause-BeforeMenu; continue }
						Add-ConfiguredModFromPrompt $kind
						Pause-BeforeMenu
						continue
					}
					4 {
						$result = Remove-ConfiguredModFromPrompt
						if ($result -ne $false) { Pause-BeforeMenu }
						continue
					}
					5 {
						Move-ConfiguredModFromPrompt
						Pause-BeforeMenu
						continue
					}
					6 {
						Clear-MenuScreen
						[void](SteamCMDFolder)
						[void](SteamCMDExe)
						$previousSelect = $select
						$select = 2
						SteamLogin
						$select = $previousSelect
						Pause-BeforeMenu
						continue
					}
					7 {
						return
					}
					Default {
						echo "`n"
						echo "Select a number from the list (1-7)."
						echo "`n"
						Pause-BeforeMenu
						continue
					}
				}
		}
}

function ModGroupManager_menu {
	while ($true)
		{
			Show-MenuHeader 'Manage Mod Groups'

			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) New group"
			echo " 2) Edit group"
			echo " 3) Rename group"
			echo " 4) Copy group"
			echo " 5) Remove group"
			echo " 6) View group"
			echo " 7) Set active group"
			echo " 8) Clear active group"
			echo " 9) Back to Main Menu"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					1 { New-ModGroupFromPrompt; Pause-BeforeMenu; continue }
					2 { Edit-ModGroupFromPrompt; Pause-BeforeMenu; continue }
					3 { Rename-ModGroupFromPrompt; Pause-BeforeMenu; continue }
					4 { Copy-ModGroupFromPrompt; Pause-BeforeMenu; continue }
					5 { Remove-ModGroupFromPrompt; Pause-BeforeMenu; continue }
					6 { $result = Show-ModGroupDetail; if ($result -ne $false) { Pause-BeforeMenu }; continue }
					7 { Select-ActiveModGroupFromPrompt; Pause-BeforeMenu; continue }
					8 { Clear-ActiveModGroupFromPrompt; Pause-BeforeMenu; continue }
					9 { return }
					Default {
						echo "`n"
						echo "Select a number from the list (1-9)."
						echo "`n"
						Pause-BeforeMenu
						continue
					}
				}
		}
}

function Select-ModGroupFromList {
	param(
		$Groups,
		[string] $Prompt,
		$CatalogSummary = $null
	)

	if (@($Groups).Count -eq 0)
		{
			Write-Host "No mod groups are defined."
			Write-Host ""
			return $null
		}

	Write-Host ""
	Write-Host " Groups:"
	Write-Host " $([string]::new([char]0x2500, 37))"
	$catalogRows = if ($CatalogSummary -and $CatalogSummary.PSObject.Properties.Name -contains 'groups') { @($CatalogSummary.groups) } else { @() }
	for ($i = 0; $i -lt $Groups.Count; $i++)
		{
			$g = $Groups[$i]
			$row = if ($i -lt $catalogRows.Count) { $catalogRows[$i] } else { $null }
			if ($row -and [string] $row.name -eq [string] $g.name)
				{
					$modCount = [int] $row.modCount
					$smCount = [int] $row.serverModCount
				}
			else
				{
					$modCount = @($g.mods).Count
					$smCount = @($g.serverMods).Count
				}
			Write-Host "  $($i + 1)) $($g.name) ($modCount mods, $smCount serverMods)"
		}
	Write-Host ""

	$raw = Read-Host -Prompt "$Prompt (0 to cancel)"
	if ($raw -eq '0') { return $null }

	$index = 0
	if (-not [int]::TryParse($raw, [ref]$index) -or $index -lt 1 -or $index -gt $Groups.Count)
		{
			Write-Host "Invalid selection."
			Write-Host ""
			return $null
		}

	return $Groups[$index - 1]
}

function New-ModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }

	$name = Read-Host -Prompt 'Enter a name for the new group'
	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	if (-not (Test-ModGroupNameValid $name $groups))
		{
			Write-Host "Invalid or duplicate group name."
			Write-Host ""
			return
		}

	$group = New-DefaultModGroup ($name.Trim())
	$result = Invoke-ModGroupChecklistEditor $config $group
	if (-not $result.Saved)
		{
			Write-Host "Cancelled - group not created."
			Write-Host ""
			return
		}

	$group.mods = @($result.Mods)
	$group.serverMods = @($result.ServerMods)
	$mission = Select-MissionFromList (Resolve-ServerFolderForMissions $config) 'Select mission'
	if ($mission)
		{
			if ($group.PSObject.Properties.Name -contains 'mission')
				{
					$group.mission = $mission
				}
			else
				{
					$group | Add-Member -NotePropertyName mission -NotePropertyValue $mission -Force
				}
		}

	$updatedConfig = Invoke-HybridGroupUpsertFromConfig `
		-Config $config `
		-GroupName $group.name `
		-ClientIds @($group.mods) `
		-ServerIds @($group.serverMods) `
		-MissionName $(if ($group.PSObject.Properties.Name -contains 'mission') { [string] $group.mission } else { $null })
	if ($updatedConfig)
		{
			$config = $updatedConfig
		}
	else
		{
			$updatedGroups = @($groups) + $group
			if ($config.PSObject.Properties.Name -contains 'modGroups')
				{
					$config.modGroups = $updatedGroups
				}
			else
				{
					$config | Add-Member -NotePropertyName modGroups -NotePropertyValue $updatedGroups -Force
				}
		}

	Save-RootConfig $config
	Write-Host "Created group '$($group.name)'."
	Write-Host ""
}

function Edit-ModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }

	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	$catalogSummary = Get-GroupCatalogSummaryFromConfig $config
	$group = Select-ModGroupFromList $groups 'Select a group to edit' $catalogSummary
	if (!$group) { return }

	$result = Invoke-ModGroupChecklistEditor $config $group
	if (-not $result.Saved)
		{
			Write-Host "Cancelled - no changes saved."
			Write-Host ""
			return
		}

	$group.mods = @($result.Mods)
	$group.serverMods = @($result.ServerMods)
	$mission = Select-MissionFromList (Resolve-ServerFolderForMissions $config) 'Select mission'
	if ($mission)
		{
			if ($group.PSObject.Properties.Name -contains 'mission')
				{
					$group.mission = $mission
				}
			else
				{
					$group | Add-Member -NotePropertyName mission -NotePropertyValue $mission -Force
				}
		}

	$updatedConfig = Invoke-HybridGroupUpsertFromConfig `
		-Config $config `
		-GroupName $group.name `
		-ExistingName $group.name `
		-ClientIds @($group.mods) `
		-ServerIds @($group.serverMods) `
		-MissionName $(if ($group.PSObject.Properties.Name -contains 'mission') { [string] $group.mission } else { $null })
	if ($updatedConfig)
		{
			$config = $updatedConfig
		}

	if ($config.activeGroup -eq $group.name)
		{
			Sync-LaunchParametersFromActiveGroup $config
		}

	Save-RootConfig $config
	Write-Host "Updated group '$($group.name)'."
	Write-Host ""
}

function Rename-ModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }
	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	$catalogSummary = Get-GroupCatalogSummaryFromConfig $config
	$group = Select-ModGroupFromList $groups 'Select a group to rename' $catalogSummary
	if (!$group) { return }

	$new = Read-Host -Prompt "New name for '$($group.name)'"
	$updatedConfig = Rename-ModGroup $config $group.name $new
	if ($updatedConfig)
		{
			$config = $updatedConfig
			Save-RootConfig $config
			Write-Host "Renamed to '$($new.Trim())'."
		}
	else
		{
			Write-Host "Invalid or duplicate name."
		}
	Write-Host ""
}

function Copy-ModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }
	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	$catalogSummary = Get-GroupCatalogSummaryFromConfig $config
	$source = Select-ModGroupFromList $groups 'Select a group to clone' $catalogSummary
	if (!$source) { return }

	$name = Read-Host -Prompt "Name for the clone of '$($source.name)'"
	if (-not (Test-ModGroupNameValid $name $groups))
		{
			Write-Host "Invalid or duplicate group name."
			Write-Host ""
			return
		}

	$clone = New-DefaultModGroup -Name ($name.Trim()) -Mods @($source.mods) -ServerMods @($source.serverMods)
	$result = Invoke-ModGroupChecklistEditor $config $clone
	if (-not $result.Saved)
		{
			Write-Host "Cancelled - clone not created."
			Write-Host ""
			return
		}

	$clone.mods = @($result.Mods)
	$clone.serverMods = @($result.ServerMods)

	$updatedConfig = Invoke-HybridGroupUpsertFromConfig `
		-Config $config `
		-GroupName $clone.name `
		-ClientIds @($clone.mods) `
		-ServerIds @($clone.serverMods) `
		-MissionName $(if ($clone.PSObject.Properties.Name -contains 'mission') { [string] $clone.mission } else { $null })
	if ($updatedConfig)
		{
			$config = $updatedConfig
		}
	else
		{
			$config.modGroups = @($groups) + $clone
		}
	Save-RootConfig $config
	Write-Host "Created clone '$($clone.name)'."
	Write-Host ""
}

function Remove-ModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }
	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	$catalogSummary = Get-GroupCatalogSummaryFromConfig $config
	$group = Select-ModGroupFromList $groups 'Select a group to delete' $catalogSummary
	if (!$group) { return }

	if ($config.activeGroup -eq $group.name)
		{
			Write-Host "Cannot delete the active group. Switch to another group first."
			Write-Host ""
			return
		}
	if (@($groups).Count -le 1)
		{
			Write-Host "Cannot delete the last remaining group."
			Write-Host ""
			return
		}

	$confirm = Read-Host -Prompt "Delete group '$($group.name)'? (y/n)"
	if ($confirm -ne 'y' -and $confirm -ne 'Y')
		{
			Write-Host "Cancelled."
			Write-Host ""
			return
		}

	$updatedConfig = Remove-ModGroup $config $group.name
	if ($updatedConfig)
		{
			$config = $updatedConfig
			Save-RootConfig $config
			Write-Host "Deleted '$($group.name)'."
		}
	else
		{
			Write-Host "Could not delete group."
		}
	Write-Host ""
}

function Clear-ActiveModGroupFromPrompt {
	$config = Get-RootConfig
	if (!$config) { return }

	if ([string]::IsNullOrWhiteSpace([string] $config.activeGroup))
		{
			Write-Host "No active group is currently set."
			Write-Host ""
			return
		}

	$updatedConfig = Set-ActiveModGroup $config ''
	if ($updatedConfig)
		{
			$config = $updatedConfig
			Save-RootConfig $config
			Write-Host "Cleared the active mod group."
		}
	else
		{
			Write-Host "Could not clear the active mod group."
		}
	Write-Host ""
}

function Show-ModGroupDetail {
	$config = Get-RootConfig
	if (!$config) { return $false }

	$groups = if ($config.PSObject.Properties.Name -contains 'modGroups') { @($config.modGroups) } else { @() }
	$catalogSummary = Get-GroupCatalogSummaryFromConfig $config
	$group = Select-ModGroupFromList $groups 'Select a group to view' $catalogSummary
	if (!$group) { return $false }

	$resolved = Get-GroupDetailFromConfig $config $group.name
	if (!$resolved)
		{
			$resolved = Resolve-ModGroupAgainstLibrary $config $group
		}

	Write-Host ""
	Write-Host " Group: $($group.name)"
	Write-Host " $([string]::new([char]0x2500, 37))"
	if ($group.PSObject.Properties.Name -contains 'mission' -and $group.mission)
		{
			Write-Host " MAP: $($group.mission)"
			Write-Host ""
		}
	Write-Host " MODS ($(@($group.mods).Count))"
	foreach ($m in $resolved.ResolvedMods)
		{
			$n = if ([string]::IsNullOrWhiteSpace($m.name)) { '(unnamed)' } else { $m.name }
			Write-Host "   $n ($($m.workshopId))"
		}
	foreach ($id in $resolved.DanglingMods)
		{
			Write-Host "   [dangling] $id"
		}
	Write-Host ""
	Write-Host " SERVER MODS ($(@($group.serverMods).Count))"
	foreach ($m in $resolved.ResolvedServerMods)
		{
			$n = if ([string]::IsNullOrWhiteSpace($m.name)) { '(unnamed)' } else { $m.name }
			Write-Host "   $n ($($m.workshopId))"
		}
	foreach ($id in $resolved.DanglingServerMods)
		{
			Write-Host "   [dangling] $id"
		}
	Write-Host ""
	return $true
}


#SteamCMD account menu
function DownloadLogin_menu {
	while ($true)
		{
			Show-MenuHeader 'SteamCMD Account'

			echo " SteamCMD uses this account for DayZ server and mod downloads."
			echo " Credentials are encrypted for the current Windows user."
			echo " Using this account once does not save your credentials."
			echo ""
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) Use account once"
			echo " 2) Save account securely"
			echo " 3) Clear saved account"
			echo " 4) Back to Main Menu"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					1 {
						echo "`n"
						[void](Prompt-SteamCmdCredential -Persist:$false)
						Pause-BeforeMenu
						return
					}

					2 {
						echo "`n"
						[void](Prompt-SteamCmdCredential -Persist:$true)
						Pause-BeforeMenu
						return
					}

					3 {
						echo "`n"
						if (Clear-SteamCmdCredential)
							{
								echo "Cleared the saved SteamCMD account."
							} else {
								echo "No saved SteamCMD account was found."
							}
						echo "`n"
						Pause-BeforeMenu
						return
					}

					4 {
						return
					}

					Default {
						echo "`n"
						echo "Select a number from the list (1-4)."
						echo "`n"
						continue
					}
				}
		}
}


#Main menu
function Menu {
	while ($true)
		{
			Show-MenuHeader (Get-ServerManagementTitle)
			Show-MainMenuStatus

			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) Update server"
			echo " 2) Update mods"
			echo " 3) Start server"
			echo " 4) Stop server"
			echo " 5) SteamCMD Account"
			echo " 6) Config Transfer"
			echo " 7) Manage mod groups"
			echo " 8) Manage mods"
			echo " 9) Remove / Uninstall"
			echo " 10) Exit"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					#Call server update and related functions
					1 {
						Clear-MenuScreen

						[void](SteamCMDFolder)
						[void](SteamCMDExe)
						SteamLogin

						Pause-BeforeMenu
						continue
					}

					#Call mods update and related functions
					2 {
						Clear-MenuScreen

						[void](SteamCMDFolder)
						[void](SteamCMDExe)
						SteamLogin

						Pause-BeforeMenu
						continue
					}

					#Start DayZ server
					3 {
						[void](SteamCMDFolder)

						$select = $null
						$script:lastServerActionSucceeded = $false
						Server_menu

						if (!$script:lastServerActionSucceeded)
							{
								Pause-BeforeMenu
							}

						continue
					}

					#Stop running server
					4 {
						$script:lastServerActionSucceeded = $false
						ServerStop

						if (!$script:lastServerActionSucceeded)
							{
								Pause-BeforeMenu
							}

						continue
					}

					#Configure SteamCMD account
					5 {
						DownloadLogin_menu
						continue
					}

					#Transfer config import/export
					#Manage mod groups
					6 {
						ConfigTransfer_menu
						continue
					}

					#Manage mod groups
					7 {
						ModGroupManager_menu
						continue
					}

					#Manage mods
					8 {
						ModManager_menu
						continue
					}

					#Purge saved login/path info
					9 {
						Remove_menu
						continue
					}

					#Close script
					10 {
						exit 0
					}

					#Force user to select one of provided options
					Default {
						echo "`n"
						echo "Select a number from the list (1-10)."
						echo "`n"

						Pause-BeforeMenu
						continue
					}
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
			Write-Host ""
			$script:folder = Read-Host -Prompt "Enter the SteamCMD folder path, or press Enter to use $recommendedFolder"
			Write-Host ""
			$folder = $script:folder

			#Check if path was really inserted
			if ([string]::IsNullOrWhiteSpace($folder))
				{
					$script:folder = $recommendedFolder
					$folder = $script:folder
					Write-Host "Using the recommended SteamCMD folder: $folder"
					Write-Host ""
				}

			Write-Host "SteamCMD folder: $folder"
			Write-Host ""

			#Create SteamCMD folder if it doesn't exist
			if (!(Test-Path "$folder"))
				{
					Write-Host "Created the SteamCMD folder."
					Write-Host ""

					mkdir "$folder" >$null
				}

			#Prompt user to save path to SteamCMD folder for future use
			Write-Host ""
			$saveFolder = Read-Host -Prompt 'Save this path for future use? (yes/no)'
			Write-Host ""

			if ( ($saveFolder -eq "yes") -or ($saveFolder -eq "y"))
				{
					#Save path to SteamCMD folder in JSON state
					$state.steamCmdPath = $folder
					Save-StateConfig $state

					Write-Host ""
					Write-Host "Saved the SteamCMD path to the state file."
					Write-Host ""
				}
		} else {
					#Use saved path to SteamCMD folder
					$script:folder = $state.steamCmdPath
					$folder = $script:folder

					Write-Host "SteamCMD folder: $folder"
					Write-Host ""

					#Create SteamCMD folder if it doesn't exist
					if (!(Test-Path "$folder"))
						{
							Write-Host "Created the SteamCMD folder."
							Write-Host ""

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
			Write-Host ""
			#Prompt user to download and install SteamCMD
			$steamInst = Read-Host -Prompt "'$folder\steamcmd.exe' was not found. Download and install SteamCMD to this folder? (yes/no)"
			Write-Host ""
			
			if ( ($steamInst -eq "yes") -or ($steamInst -eq "y"))
				{
					Write-Host "Downloading and installing SteamCMD..."
					Write-Host ""

                    #Get Powershell version for compatibility check
					$psVer = $PSVersionTable.PSVersion.Major

                    if ($psVer -gt 3)
	                    {

				            Write-Host "Using PowerShell version $psVer"
							Write-Host ""

                            #Download SteamCMD
                            $downloadURL = Get-SteamCmdDownloadUrl
                            $destPath = "$folder\steamcmd.zip"

                            # Ensure TLS 1.2 is available for HTTPS downloads
                            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                            $downloadSuccess = $false

                            # Method 1: Invoke-WebRequest
                            if (!$downloadSuccess)
                                {
                                    try
                                        {
                                            Write-Host "Downloading via Invoke-WebRequest..."
                                            Invoke-WebRequest -Uri $downloadURL -OutFile $destPath -UseBasicParsing -ErrorAction Stop
                                            if (Test-Path -LiteralPath $destPath) { $downloadSuccess = $true }
                                        }
                                    catch
                                        {
                                            Write-Host "Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor Yellow
                                        }
                                }

                            # Method 2: System.Net.WebClient
                            if (!$downloadSuccess)
                                {
                                    try
                                        {
                                            Write-Host "Trying WebClient..."
                                            $wc = New-Object System.Net.WebClient
                                            $wc.DownloadFile($downloadURL, $destPath)
                                            if (Test-Path -LiteralPath $destPath) { $downloadSuccess = $true }
                                        }
                                    catch
                                        {
                                            Write-Host "WebClient failed: $($_.Exception.Message)" -ForegroundColor Yellow
                                        }
                                    finally
                                        {
                                            if ($wc) { $wc.Dispose() }
                                        }
                                }

                            # Method 3: Start-BitsTransfer
                            if (!$downloadSuccess)
                                {
                                    try
                                        {
                                            Write-Host "Trying BITS transfer..."
                                            Start-BitsTransfer -Source $downloadURL -Destination $destPath -ErrorAction Stop
                                            if (Test-Path -LiteralPath $destPath) { $downloadSuccess = $true }
                                        }
                                    catch
                                        {
                                            Write-Host "BITS transfer failed: $($_.Exception.Message)" -ForegroundColor Yellow
                                        }
                                }

                            if (!$downloadSuccess)
                                {
                                    Write-Host ""
                                    Write-Host "All download methods failed." -ForegroundColor Red
                                    Write-Host "Download SteamCMD manually from:"
                                    Write-Host "  $downloadURL"
                                    Write-Host "and extract it to: $folder"
                                    Write-Host ""
                                    if ($script:startupBootstrapActive) { return $false }
                                    pause
                                    Menu
                                    return $false
                                }

                            #Verify download
                            if (!(Test-Path -LiteralPath $destPath))
                                {
                                    Write-Host "Download appeared to succeed but steamcmd.zip was not found at $destPath" -ForegroundColor Red
                                    Write-Host ""
                                    if ($script:startupBootstrapActive) { return $false }
                                    pause
                                    Menu
                                    return $false
                                }

                            $zipSize = (Get-Item -LiteralPath $destPath).Length
                            Write-Host "Downloaded steamcmd.zip ($zipSize bytes)"

                            #Unzip SteamCMD
                            Write-Host "Extracting..."
                            try
                                {
                                    Expand-Archive -LiteralPath $destPath -DestinationPath "$folder" -Force -ErrorAction Stop
                                }
                            catch
                                {
                                    Write-Host "Expand-Archive failed: $($_.Exception.Message)" -ForegroundColor Yellow
                                    Write-Host "Trying Shell.Application fallback..."
                                    try
                                        {
                                            $shell = New-Object -ComObject Shell.Application
                                            $zipFile = $shell.NameSpace($destPath)
                                            $unzipPath = $shell.NameSpace("$folder")
                                            $copyFlags = 0x04 -bor 0x10
                                            $unzipPath.CopyHere($zipFile.Items(), $copyFlags)
                                        }
                                    catch
                                        {
                                            Write-Host "Shell extraction also failed: $($_.Exception.Message)" -ForegroundColor Red
                                            Write-Host ""
                                            if ($script:startupBootstrapActive) { return $false }
                                            pause
                                            Menu
                                            return $false
                                        }
                                }

							$steamCmdExe = Join-Path $folder 'steamcmd.exe'
                            if (!(Test-Path -LiteralPath $steamCmdExe))
                                {
                                    Write-Host "Extraction completed but steamcmd.exe was not found in $folder" -ForegroundColor Red
                                    Write-Host ""
                                    if ($script:startupBootstrapActive) { return $false }
                                    pause
                                    Menu
                                    return $false
                                }

						#If Powershell version is under 4
			            } else {
						            Write-Host ""
									Write-Host "PowerShell version $psVer is not supported." -ForegroundColor Red
									Write-Host ""
					           }

					#Run SteamCMD self-update before signature check - the
					#bootstrapper from the zip is not fully signed until it
					#updates itself on first run.
					Write-Host "Running SteamCMD self-update..."
					Start-Process -FilePath "$folder\steamcmd.exe" -ArgumentList ('+quit') -Wait -NoNewWindow

					Start-Sleep -Seconds 1

					#Verify signature after self-update
					$steamCmdExe = Join-Path $folder 'steamcmd.exe'
					if (Test-Path -LiteralPath $steamCmdExe)
						{
							Write-Host "Verifying signature..."
							if (!(Test-ExpectedSigner $steamCmdExe 'Valve Corp\.'))
								{
									Write-Host "steamcmd.exe does not have a valid Valve signature after self-update." -ForegroundColor Yellow
									Write-Host "Proceeding anyway - verify the file manually if concerned."
									Write-Host ""
								}
						}

					if (Test-Path "$folder\steamcmd.exe")
						{
							#Remove SteamCMD zip file after successful installation
							Remove-Item -Path "$folder\steamcmd.zip" -Force -ErrorAction SilentlyContinue
							
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

# DEPRECATED: This function exposes the password on the process command
# line. Use New-SteamCmdLoginScript with +runscript instead. Kept only
# for backward compatibility with existing tests.
function Get-SteamCmdLoginArguments {
	param(
		[System.Management.Automation.PSCredential] $Credential
	)

	if (!$Credential)
		{
			$Credential = Get-ActiveSteamCmdCredential
		}
	if (!$Credential)
		{
			throw [System.InvalidOperationException] 'Steam account credentials are required to download and update DayZ server files and mods.'
		}

	return @('+login', $Credential.UserName, $Credential.GetNetworkCredential().Password)
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

# Builds a single argument string for System.Diagnostics.Process using
# CommandLineToArgvW parsing rules. Handles spaces and embedded quotes
# but does not handle backslash-before-quote edge cases. SteamCMD
# arguments are simple enough that this is not expected to cause issues.
function ConvertTo-SteamCmdArgumentString {
	param([string[]] $Arguments)

	if (-not $Arguments)
		{
			return ''
		}

	$parts = @()
	foreach ($arg in $Arguments)
		{
			$value = [string] $arg
			if ($value -eq '')
				{
					$parts += '""'
					continue
				}
			if ($value -notmatch '[\s"]')
				{
					$parts += $value
					continue
				}
			$escaped = $value -replace '"', '\"'
			$parts += '"' + $escaped + '"'
		}

	return ($parts -join ' ')
}

function Invoke-SteamCmdCommand {
	param([string[]] $Arguments)

	# Launch steamcmd via System.Diagnostics.Process so it inherits the
	# parent's console handles directly. UseShellExecute=$false with no
	# Redirect* flags hands the child the real stdin/stdout/stderr at the
	# OS level, so PowerShell's success stream never sees the output. This
	# is required because callers do `$proc = Invoke-SteamCmdCommand(...)` -
	# any stdout we routed through PowerShell would be swallowed by that
	# outer capture and the Steam Guard prompt would never reach the user.
	#
	# We use the legacy Arguments string (with manual escaping) instead of
	# ArgumentList because ArgumentList is .NET Core 2.1+ only and is not
	# available under Windows PowerShell 5.1 / .NET Framework.
	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = "$folder\steamcmd.exe"
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $false
	$psi.Arguments = ConvertTo-SteamCmdArgumentString $Arguments

	$proc = [System.Diagnostics.Process]::Start($psi)
	$proc.WaitForExit()
	$exitCode = $proc.ExitCode
	$proc.Dispose()

	return [pscustomobject]@{
		ExitCode = $exitCode
		Output   = ''
		StdOut   = ''
		StdErr   = ''
	}
}

function Write-SteamCmdFailureGuidance {
	param(
		[int] $ExitCode,
		[string] $Output,
		[string] $Operation
	)

	if (Test-SteamCmdSignInFailure -ExitCode $ExitCode -Output $Output)
		{
			Write-Host "SteamCMD sign-in failed for the saved Steam account."
			Write-Host "If Steam Guard is enabled, approve the sign-in in the Steam app and retry."
			Write-Host "If Steam Guard uses email, SteamCMD will ask for the code in this same window after you enter your password."
			Write-Host "Re-enter your Steam credentials if your password has changed."
			Write-Host ""
			return
		}

	if ($Output -match 'No subscription')
		{
			Write-Host "Steam denied access to DayZ Server for the saved account."
			Write-Host "Check that this Steam account owns DayZ and complete any Steam Guard app approval or email code check, then retry."
			Write-Host ""
		}
}

function Test-SteamCmdSignInFailure {
	param(
		[int] $ExitCode,
		[string] $Output
	)

	return (($ExitCode -eq 5) -or ($Output -match 'Invalid Password|Login Failure|Steam Guard|two-factor|Two-factor'))
}

function Request-SteamCmdRetryCredential {
	Write-Host "Steam sign-in failed"
	Write-Host "-------------------"
	Write-Host "Choose how to retry the SteamCMD account sign-in."
	Write-Host "If Steam Guard uses email, SteamCMD will ask for the code in this same window after you enter your password."
	Write-Host "1) Re-enter account once"
	Write-Host "2) Clear saved account and re-enter"
	Write-Host "3) Cancel"
	Write-Host ""

	while ($true)
		{
			$select = Read-Host -Prompt 'Select a retry option'

			switch ($select)
				{
					'1' {
						$credential = Prompt-SteamCmdCredential -Persist:$false
						if ($credential)
							{
								return [pscustomobject]@{
									Credential = $credential
									SaveOnSuccess = $false
								}
							}

						return $null
					}
					'2' {
						$credential = Prompt-SteamCmdCredential -Persist:$false -PendingSave
						if ($credential)
							{
								return [pscustomobject]@{
									Credential = $credential
									SaveOnSuccess = $true
								}
							}

						return $null
					}
					'3' {
						Write-Host "Retry was canceled."
						Write-Host ""
						return $null
					}
					default {
						Write-Host "Select a number from the list (1-3)."
						Write-Host ""
					}
				}
		}
}

function Invoke-SteamCmdAuthenticatedOperation {
	param(
		[string] $Operation,
		[string[]] $Arguments
	)

	$credential = Resolve-SteamCmdDownloadCredential
	if (!$credential)
		{
			echo "SteamCMD account was not configured."
			echo "Open Configure SteamCMD account and try again."
			echo "`n"
			return $null
		}

	# Write credentials to an ephemeral runscript file so the password
	# never appears on the steamcmd.exe command line (visible in Task
	# Manager / process list). The file is deleted in the finally block.
	$loginScriptPath = New-SteamCmdLoginScript -Credential $credential -Path $tempLoginScript
	try
		{
			$proc = Invoke-SteamCmdCommand (@('+runscript', $loginScriptPath) + $Arguments)
		}
	finally
		{
			Remove-Item -LiteralPath $loginScriptPath -Force -ErrorAction SilentlyContinue
		}
	if ($proc.ExitCode -eq 0)
		{
			Clear-SteamCmdLastSignInFailed
			return $proc
		}

	if (Test-SteamCmdSignInFailure -ExitCode $proc.ExitCode -Output $proc.Output)
		{
			Set-SteamCmdLastSignInFailed
			Write-SteamCmdFailureGuidance $proc.ExitCode $proc.Output $Operation

			$previousSessionCredential = Get-SteamCmdSessionCredential
			$retrySelection = Get-SteamCmdRetryCredential
			if ($retrySelection -is [System.Management.Automation.PSCredential])
				{
					$retryCredential = $retrySelection
					$saveRetryCredentialOnSuccess = $false
				} else {
					$retryCredential = $retrySelection.Credential
					$saveRetryCredentialOnSuccess = [bool] $retrySelection.SaveOnSuccess
				}
			if (!$retryCredential)
				{
					echo "SteamCMD $Operation failed with exit code $($proc.ExitCode)."
					return $proc
				}

			$retryLoginScriptPath = New-SteamCmdLoginScript -Credential $retryCredential -Path $tempLoginScript
			try
				{
					$retryProc = Invoke-SteamCmdCommand (@('+runscript', $retryLoginScriptPath) + $Arguments)
				}
			finally
				{
					Remove-Item -LiteralPath $retryLoginScriptPath -Force -ErrorAction SilentlyContinue
				}
			if ($retryProc.ExitCode -eq 0)
				{
					if ($saveRetryCredentialOnSuccess)
						{
							Save-SteamCmdCredential $retryCredential
							# The retry prompt set the session credential
							# as a side effect of -Persist:$false. Clear
							# it now so the status helper reports 'Saved'
							# (not 'Session only') after the successful
							# replacement.
							Clear-SteamCmdSessionCredential
						}
					Clear-SteamCmdLastSignInFailed
					return $retryProc
				}

			if ($previousSessionCredential)
				{
					Set-SteamCmdSessionCredential $previousSessionCredential
				} else {
					Clear-SteamCmdSessionCredential
				}

			if (Test-SteamCmdSignInFailure -ExitCode $retryProc.ExitCode -Output $retryProc.Output)
				{
					Set-SteamCmdLastSignInFailed
					Write-SteamCmdFailureGuidance $retryProc.ExitCode $retryProc.Output $Operation
				} else {
					Clear-SteamCmdLastSignInFailed
				}

			echo "SteamCMD $Operation failed with exit code $($retryProc.ExitCode)."
			return $retryProc
		}

	return $proc
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
	$proc = Invoke-SteamCmdAuthenticatedOperation -Operation 'server update' -Arguments @('+app_update', $steamApp, 'validate', '+quit')
	if ($proc.ExitCode -ne 0)
		{
			echo "SteamCMD server update failed with exit code $($proc.ExitCode)."
			return
		}

	Start-Sleep -Seconds 1

	echo "`n"
	echo "DayZ server was updated to the latest version."
	echo "`n"

}

#Update mods
function ModsUpdate {
	
	#Path to DayZ server folder
	$serverFolder = Join-Path $folder $appFolder.TrimStart('\') 
	
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
					
					Show-ModUpdateSummary $rootConfig $mods $serverMods $wrongId $wrongServerId

					#Path to SteamCMD DayZ Workshop content folder
					$workshopFolder = Join-Path $folder 'steamapps\workshop\content\221100'

					#Combine all mod IDs into a single download script so SteamCMD
					#only needs to log in once instead of making two separate sessions.
					$allDownloadIds = @($mods) + @($serverMods)

					if ($allDownloadIds.Count -gt 0)
						{
							New-WorkshopDownloadScript $allDownloadIds "$tempModList"

							$totalCount = $allDownloadIds.Count
							echo "Downloading $totalCount mod(s) in a single session..."
							echo "`n"

							try
								{
									$proc = Invoke-SteamCmdAuthenticatedOperation -Operation 'mod update' -Arguments @('+runscript', "$tempModList")
									if ($proc.ExitCode -ne 0)
										{
											echo "SteamCMD workshop update failed with exit code $($proc.ExitCode)."
											return
										}

									Start-Sleep -Seconds 1
								}
							finally
								{
									Remove-Item -Path "$tempModList" -Force -ErrorAction SilentlyContinue
								}
						}

					#Copy downloaded client mods to server folder
					if ($mods.Count -gt 0)
						{
							if (!(Test-WorkshopItemsPresent $workshopFolder $mods))
								{
									echo "One or more requested client mod folders are missing after SteamCMD update. Aborting copy."
									return
								}

							foreach ($mod in $mods)
								{
									robocopy (Join-Path $workshopFolder $mod) (Join-Path $serverFolder $mod) /E /is /it /np /njs /njh /ns /nc /ndl /nfl
									if ($LASTEXITCODE -gt 7)
										{
											echo "Copy failed for mod $mod with robocopy exit code $LASTEXITCODE."
											return
										}
								}

							foreach ($mod in $mods)
								{
									$keyPath = Join-Path (Join-Path $serverFolder $mod) 'keys'
									if (Test-Path -LiteralPath $keyPath -PathType Container)
										{
											Copy-Item -Path (Join-Path $keyPath '*.bikey') -Destination (Join-Path $serverFolder 'keys') -ErrorAction SilentlyContinue
										}
								}

							Write-Host " $([char]0x2713) Copied $($mods.Count) client mod(s) and keys" -ForegroundColor Green
						}

					#Copy downloaded server mods to server folder
					if ($serverMods.Count -gt 0)
						{
							if (!(Test-WorkshopItemsPresent $workshopFolder $serverMods))
								{
									echo "One or more requested server mod folders are missing after SteamCMD update. Aborting copy."
									return
								}

							foreach ($serverMod in $serverMods)
								{
									robocopy (Join-Path $workshopFolder $serverMod) (Join-Path $serverFolder $serverMod) /E /is /it /np /njs /njh /ns /nc /ndl /nfl
									if ($LASTEXITCODE -gt 7)
										{
											echo "Copy failed for server mod $serverMod with robocopy exit code $LASTEXITCODE."
											return
										}
								}

							foreach ($serverMod in $serverMods)
								{
									$keyPath = Join-Path (Join-Path $serverFolder $serverMod) 'keys'
									if (Test-Path -LiteralPath $keyPath -PathType Container)
										{
											Copy-Item -Path (Join-Path $keyPath '*.bikey') -Destination (Join-Path $serverFolder 'keys') -ErrorAction SilentlyContinue
										}
								}

							Write-Host " $([char]0x2713) Copied $($serverMods.Count) server mod(s) and keys" -ForegroundColor Green
						}

					Write-Host ""

					Set-GeneratedLaunchMods $mods $serverMods

				}
}

#Run DayZ server with mods
function Server_menu {
	
	#Path to server folder
	$serverFolder = Join-Path $folder $appFolder.TrimStart('\')
	
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

										Write-Host " $([string]::new([char]0x2500, 37))"
							            echo " 1) Use saved launch parameters"
							            echo " 2) Use default launch parameters"
							            echo " 3) Back"
										Write-Host " $([string]::new([char]0x2500, 37))"
							            echo ""

							            $select = Read-Host -Prompt 'Select an option'

                                        Server_menu

                                        return
                                }
                            
                            #Use user provided server parameters
                            1 {
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
								
										if (-not (Test-SafeLaunchParameters $serverPar))
											{
												echo "The saved launch parameters contain characters that are not allowed. Check your configuration."
												echo "`n"
												$script:lastServerActionSucceeded = $false
												return
											}

								        echo "Starting the DayZ server with saved launch parameters..."
								        echo "`n"

								        #Run server
										$serverExe = Join-Path $serverFolder 'DayZServer_x64.exe'
								        $procServer = Start-Process -FilePath "$serverExe" -PassThru -ArgumentList "`"-bepath=$serverFolder\battleye`" $serverPar"
										
								        #Save server process metadata for future use
										Add-TrackedServerRecord $procServer $serverExe
										
								        Start-Sleep -Seconds 5	
										
								        echo "The DayZ server is now running."
								        echo "`n"

                                        $script:lastServerActionSucceeded = $true
										return
                                }
                            
                            #Use default server parameters
                            2 {
									echo "Starting the DayZ server with default launch parameters..."
									echo "`n"

									#Run server
									$serverExe = Join-Path $serverFolder 'DayZServer_x64.exe'
									$procServer = Start-Process -FilePath "$serverExe" -PassThru -ArgumentList "`"-config=$serverFolder\serverDZ.cfg`" `"-mod=$modsServer`" `"-serverMod=$serverModsServer`" `"-bepath=$serverFolder\battleye`" `"-profiles=$serverFolder\logs`" -port=2302 -freezecheck -adminlog -dologs"
										
									#Save server process metadata for future use
									Add-TrackedServerRecord $procServer $serverExe
										
									Start-Sleep -Seconds 5	
										
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

    $serverFolder = Join-Path $folder $appFolder.TrimStart('\')
	$appManifestPath = Get-SteamAppManifestPath $folder $steamApp
														
	#Uninstall DayZ server
	$proc = Invoke-SteamCmdCommand (Get-SteamCmdUninstallArguments $steamApp)
	if ($proc.ExitCode -ne 0)
		{
			echo "SteamCMD app_uninstall failed with exit code $($proc.ExitCode)."
		}
																											
	Start-Sleep -Seconds 1
    
    #Check if server was deleted and if not removed it forcefully
    if (Test-Path "$serverFolder")
        {
            if (Test-SafeServerFolderForRemoval $serverFolder)
                {
                    Remove-Item -Path "$serverFolder" -Recurse -Force
                } else {
                    echo "The server folder path does not appear safe for automatic removal: $serverFolder"
                    echo "`n"
                }
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
	while ($true)
		{
			Show-MenuHeader 'Remove / Uninstall'

			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) Clear saved SteamCMD path"
			echo " 2) Remove mod files"
			echo " 3) Uninstall DayZ server"
			echo " 4) Uninstall SteamCMD"
			echo " 5) Back to Main Menu"
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			switch ($select)
				{
					#Remove stored path to SteamCMD folder
					1 {
						$state = Get-StateConfig
						$state.steamCmdPath = $null
						Save-StateConfig $state

						echo "Cleared the saved SteamCMD path."
						echo "`n"

						Pause-BeforeMenu
						continue
					}

					#Select mod and remove it
					2 {
						$reminder = $false

						#Prompt user to insert workshop id or workshop url for the mod to remove
						$rawRemMod = Read-Host -Prompt 'Enter the mod ID you want to remove'
						$rem_mod = Get-WorkshopIdFromInput $rawRemMod
						if ([string]::IsNullOrWhiteSpace($rem_mod))
							{
								echo "`n"
								echo "No valid mod ID was entered. Returning to Remove / Uninstall."
								echo "`n"
								continue
							}

						echo "`n"

						[void](SteamCMDFolder)

						#Path to SteamCMD DayZ Workshop content folder
						$workshopFolder = Join-Path $folder 'steamapps\workshop\content\221100'

						#Path to DayZ server folder
						$serverFolder = Join-Path $folder $appFolder.TrimStart('\')

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

						continue
					}

					#Uninstall DayZ server
					3 {
						#Prompt user for DayZ server uninstall confirmation
						$rem_server = Read-Host -Prompt 'Uninstall the DayZ server? (yes/no)'

						echo "`n"

						if ( ($rem_server -eq "yes") -or ($rem_server -eq "y"))
							{
								[void](SteamCMDFolder)
								[void](SteamCMDExe)
								ServerUninstall
							}

						continue
					}

					#Uninstall SteamCMD
					4 {
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
										continue
									}

								$confirmFolder = Read-Host -Prompt "Type the full SteamCMD folder path to confirm removal"
								if ($confirmFolder -ne $folder)
									{
										echo "The confirmation path did not match. The SteamCMD folder was not removed."
										echo "`n"
										continue
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

						continue
					}

					#Return to previous menu
					5 {
						return
					}

					#Force user to select one of provided options
					Default {
						echo "`n"
						echo "Select a number from the list (1-5)."
						echo "`n"
						continue
					}
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
	while ($true)
		{
			Show-MenuHeader (Get-MainMenuTitle)

			$state = Get-StateConfig
			if (Test-UpdateCheckShouldShowIndicator $state.updateCheck $script:serverManagerVersion)
				{
					Write-Host (Format-UpdateCheckIndicator $script:serverManagerVersion $state.updateCheck.latestVersion) -ForegroundColor Yellow
					Write-Host ''
				}

			$showInstall = Test-UpdateApplyAvailable $state $script:serverManagerVersion

			Write-Host " $([string]::new([char]0x2500, 37))"
			echo " 1) Stable server"
			echo " 2) Experimental server"
			if ($showInstall)
				{
					echo " 3) Install available update"
					echo " 4) Exit"
				}
			else
				{
					echo " 3) Exit"
				}
			Write-Host " $([string]::new([char]0x2500, 37))"
			echo ""

			$select = Read-Host -Prompt 'Select an option'

			if ($showInstall -and $select -eq '3')
				{
					Invoke-UpdateApply
					continue
				}

			$exitOption = if ($showInstall) { '4' } else { '3' }
			if ($select -eq $exitOption)
				{
					exit 0
				}

			switch ($select)
				{
					#Steam Stable server app
					1 {
						Set-SelectedServerApp 'stable'

						Menu
						continue
					}

					#Steam Experimental server app
					2 {
						Set-SelectedServerApp 'exp'

						Menu
						continue
					}

					#Force user to select one of provided options
					Default {
						$maxOption = if ($showInstall) { '4' } else { '3' }
						echo "`n"
						echo "Select a number from the list (1-$maxOption)."
						echo "`n"

						Pause-BeforeMenu
						continue
					}
				}
		}
}

#Open Main menu if launch parameters are not used
if (!$script:ServerManagerSkipAutoRun)
	{
		if (-not (Test-HybridPythonPrerequisite))
			{
				exit 1
			}

		Initialize-ConfigFiles
		Invoke-UpdateCheckStartup

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
