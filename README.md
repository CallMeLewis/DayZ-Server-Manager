# DayZ Server Manager

PowerShell script for downloading, updating, and managing a DayZ dedicated server and its Workshop mods.

## Attribution

This repository is an updated version of the original `Server_manager.ps1` provided by Bohemia Interactive.

I am not claiming authorship of the original server manager script. This project is a maintained and modified version of Bohemia Interactive's original work.

## Overview

`Server_manager.ps1` can:

- Download or update SteamCMD
- Download or update DayZ server files
- Download or update configured Workshop mods
- Start the DayZ server with default or user launch parameters
- Stop tracked DayZ server processes
- Manage client and server mod lists from the interactive menu

## Requirements

- PowerShell 4 or newer
- Windows 10, Windows Server 2012 R2, or newer
- SteamCMD

## Main Files

- `Server_manager.ps1`: main script
- `Start_Server_Manager.cmd`: double-click launcher for File Explorer use
- `server-manager.config.json`: root config stored next to the script

## Configuration

The manager uses two JSON files.

### Root Config

Stored in the repository folder:

`server-manager.config.json`

This file contains the persistent manager configuration:

- `launchParameters`
- `mods`
- `serverMods`

### Saved State

Stored in the current Windows user documents folder:

`%USERPROFILE%\Documents\DayZ_Server\server-manager.state.json`

This file contains the current runtime state used by the manager:

- SteamCMD path
- Generated launch mod strings
- Tracked DayZ server process metadata

Workshop downloads and server updates use anonymous SteamCMD login only. Private or account-restricted Workshop content is not supported by this automation path.

## Usage

### Interactive Menu

```powershell
.\Server_manager.ps1
```

### Command Line Parameters

| Parameter | Values | Description |
| --- | --- | --- |
| `-u` / `-update` | `server`, `mod`, `all` | Update the server, mods, or both |
| `-s` / `-server` | `start`, `stop` | Start the server or stop running server processes |
| `-lp` / `-launchParam` | `default`, `user` | Select which launch parameters to use when starting |
| `-app` | `stable`, `exp` | Select the stable or experimental DayZ server app |

## Examples

Open the main menu:

```powershell
.\Server_manager.ps1
```

Update the experimental server:

```powershell
.\Server_manager.ps1 -update server -app exp
```

Update both server and mods and start with the configured `launchParameters` value from `server-manager.config.json`:

```powershell
.\Server_manager.ps1 -u all -s start -lp user
```

Stop tracked DayZ server processes started by this script:

```powershell
.\Server_manager.ps1 -s stop
```

Show help for a specific parameter:

```powershell
Get-Help .\Server_manager.ps1 -Parameter update
```

## Mod Management

Use the `Manage mods` menu to:

- List client mods
- List server mods
- Add mods
- Move mods between client and server lists
- Remove mods from config

## Double-Click Launch

Use `Start_Server_Manager.cmd` to run the manager from File Explorer without opening a terminal first. The launcher keeps the window open after the script exits so the output remains visible.

The launcher now respects your local PowerShell execution policy. If you edit the local copy, you may need to unblock or re-sign it depending on your policy settings.

## References

- [DayZ](https://dayz.com/)
- [DayZ Official Forums](https://forums.dayz.com/forum/136-official/)
- [DayZ Wiki: Server_manager](https://community.bistudio.com/wiki/DayZ:Server_manager)
