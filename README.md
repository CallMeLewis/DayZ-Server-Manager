# DayZ Server Manager

Windows-focused DayZ server manager for downloading, updating, and running a DayZ dedicated server and its Workshop mods without needing to manage every SteamCMD step by hand.

## What It Does

- Downloads or updates SteamCMD
- Downloads or updates DayZ server files
- Downloads or updates configured Workshop mods in a single SteamCMD session
- Starts and stops tracked DayZ server processes
- Manages client mods, server mods, and named mod groups from the menu
- Checks for and installs new manager releases from GitHub
- Exports and imports config for backups or machine moves

## Quick Start

### Requirements

- Windows 10, Windows Server 2012 R2, or newer
- PowerShell 4 or newer
- Python 3 installed on the host
- A Steam account that owns DayZ for server and Workshop downloads

The launcher runs a dependency preflight on startup. If Python 3 is missing, it stops and prints the install command you need.

### Launch From PowerShell

```powershell
.\windows\Server_manager.ps1
```

### Launch From File Explorer

Double-click `windows\Start_Server_Manager.cmd`.

The launcher keeps the window open after the script exits so you can still read the output.

The launcher automatically unblocks `Server_manager.ps1` after a release zip download, so `RemoteSigned` no longer blocks the unsigned script in normal use.

## Core Features

### SteamCMD Account Handling

The manager does not ask for Steam credentials on startup. It only asks when you actually update the server or mods.

- `Use account once` keeps the login in memory for the current PowerShell session only
- `Save account securely` stores the login in Windows Credential Manager for the current Windows user
- If an older release stored credentials in `server-manager.state.json`, they are migrated automatically on first launch
- If Steam Guard uses email, SteamCMD prompts for the code in the same console window

Credentials are never passed on the SteamCMD command line. The manager uses a temporary runscript file and deletes it after use.

### Mod Groups

Mod groups let you save and switch between named server setups.

- Create, edit, rename, clone, delete, or view groups from `Manage mod groups`
- Switch the active group in one step to rewrite `-mod` and `-serverMod`
- The first run migrates your current launch parameters into a `Default` group
- Each group can store a mission folder, and switching groups updates `template` in `serverDZ.cfg`

### In-App Update Check And Install

On launch, the manager checks GitHub for a newer release with a short timeout and cached results.

- A one-time full-screen notice appears when a newer version is available
- A persistent `* Update available: vX.Y.Z` indicator stays on the main menu
- `Install available update` downloads the packaged Windows release zip and applies it for you
- Files being replaced are backed up to `.update-backup/`
- If apply fails mid-update, the backup is restored automatically

Scripted runs such as `-u` and `-s` skip the update check.

### Config Transfer

The `Config Transfer` menu helps with backups and moving to another machine.

- `Export config` writes a portable JSON envelope of your config
- `Import config` validates that file before replacing your current config
- The current config is backed up as `.import.bak` before import overwrite

Exports intentionally do not include Steam account credentials or runtime state.

## Where Files Live

### Config File

Stored per user in the Windows Documents folder:

`<Documents>\DayZ_Server\server-manager.config.json`

This file contains your persistent manager configuration, including:

- `launchParameters`
- `mods`
- `serverMods`
- `modGroups`
- `activeGroup`

Older installs that kept config beside `windows/Server_manager.ps1` are migrated automatically on first upgraded run and backed up as `.legacy.bak`.

### State File

Stored per user in the Windows Documents folder:

`<Documents>\DayZ_Server\server-manager.state.json`

This file contains runtime state such as:

- SteamCMD path
- Last SteamCMD sign-in status
- Generated launch mod strings
- Tracked DayZ server process metadata

The state file is restricted to the current Windows user via file permissions.

### Saved Credentials

Saved Steam credentials are not stored in `server-manager.state.json`.

They are stored in Windows Credential Manager under the current Windows user profile. One-time logins remain session-only and are not written there.

## Basic Usage

### Interactive Flow

On first run, the script sets up SteamCMD and does not ask for Steam credentials yet.

When you choose `Update server` or `Update mods`, the manager will:

- use the saved SteamCMD account if one is already configured
- otherwise prompt you to `Use account once` or `Save account securely`
- let you clear the saved SteamCMD account from `SteamCMD Account`

If SteamCMD sign-in fails, the manager shows guided retry options and marks the main menu status as `Last sign-in failed` until the login is corrected.

### Command Line Parameters

| Parameter | Values | Description |
| --- | --- | --- |
| `-u` / `-update` | `server`, `mod`, `all` | Update the server, mods, or both |
| `-s` / `-server` | `start`, `stop` | Start the server or stop running server processes |
| `-lp` / `-launchParam` | `default`, `user` | Select which launch parameters to use when starting |
| `-app` | `stable`, `exp` | Select the stable or experimental DayZ server app |

### Examples

Open the main menu:

```powershell
.\windows\Server_manager.ps1
```

Update the experimental server:

```powershell
.\windows\Server_manager.ps1 -update server -app exp
```

Update both server and mods, then start with configured user launch parameters:

```powershell
.\windows\Server_manager.ps1 -u all -s start -lp user
```

Stop tracked DayZ server processes started by this script:

```powershell
.\windows\Server_manager.ps1 -s stop
```

## Need More Detail?

- Steam credential handling and security: [STEAMCMD-CREDENTIALS.md](./STEAMCMD-CREDENTIALS.md)
- PowerShell parameter help:

```powershell
Get-Help .\windows\Server_manager.ps1 -Parameter update
```

## Attribution

This repository is an updated version of the original `windows/Server_manager.ps1` provided by Bohemia Interactive.

I am not claiming authorship of the original server manager script. This project is a maintained and modified version of Bohemia Interactive's original work.
