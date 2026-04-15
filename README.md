# DayZ Server Manager

PowerShell script for downloading, updating, and managing a DayZ dedicated server and its Workshop mods.

## Attribution

This repository is an updated version of the original `windows/Server_manager.ps1` provided by Bohemia Interactive.

I am not claiming authorship of the original server manager script. This project is a maintained and modified version of Bohemia Interactive's original work.

## Overview

`windows/Server_manager.ps1` can:

- Download or update SteamCMD
- Download or update DayZ server files
- Download or update configured Workshop mods (single SteamCMD session for all mods)
- Start the DayZ server with default or user launch parameters
- Stop tracked DayZ server processes
- Manage client and server mod lists from the interactive menu
- Manage mod groups: named mod profiles you can switch in one step

## Linux Manager

The Linux rewrite uses `linux/server_manager_linux.sh` as the interactive entrypoint.

It targets Ubuntu 24.04 x86_64.

It is systemd-first: the menu routes start, stop, restart, status, and reload actions through `systemctl`, and the DayZ server runs as a background service instead of a foreground shell process.

## New: Mod Groups

Mod groups let you save multiple named mod profiles and swap them in seconds.

- Create, edit, rename, clone, delete, or view groups from `Manage mod groups`
- Switch the active group from the main menu to instantly rewrite `-mod` and `-serverMod`
- The first run migrates your current launch parameters into a `Default` group
- Store a map (mission folder) per group; switching groups updates `template` in `serverDZ.cfg`

## Requirements

- PowerShell 4 or newer
- Windows 10, Windows Server 2012 R2, or newer
- SteamCMD
- A Steam account that owns DayZ for server and Workshop downloads

## Main Files

- `windows/Server_manager.ps1`: Windows main script
- `windows/server-manager.config.json`: local Windows config stored next to the script and kept out of git
- `windows/Start_Server_Manager.cmd`: Windows double-click launcher for File Explorer use
- `linux/server_manager_linux.sh`: Linux interactive entrypoint
- `linux/lib/linux_manager.sh`: Linux helper library
- `linux/templates/dayz-server.service.template`: systemd unit template
- `STEAMCMD-CREDENTIALS.md`: explains how SteamCMD credentials are stored and passed to SteamCMD

## Configuration

The manager uses two JSON files.

### Windows Config

Stored locally next to the Windows script:

`windows/server-manager.config.json`

This file contains the persistent manager configuration:

- `launchParameters`
- `mods`
- `serverMods`

### Saved State

Stored in the current Windows user documents folder:

Located in the system Documents folder (supports redirected or roaming profiles):

`<Documents>\DayZ_Server\server-manager.state.json`

This file contains the current runtime state used by the manager:

- SteamCMD path
- Saved SteamCMD account state
- Generated launch mod strings
- Tracked DayZ server process metadata

The state file is restricted to the current Windows user via file permissions.

Saved SteamCMD account credentials (username and password) are encrypted using Windows DPAPI and can only be decrypted by the same Windows user on the same machine. You can also choose a one-time account login that is kept only for the current PowerShell session.

Credentials are never passed on the SteamCMD command line. Instead, they are written to a temporary runscript file that is deleted immediately after use. See `STEAMCMD-CREDENTIALS.md` for full details.

If Steam Guard is enabled, SteamCMD may require either Steam app confirmation or an email code during sign-in. When Steam Guard uses email, SteamCMD asks for that code in the same console window after the password step.

## Usage

### Interactive Menu

```powershell
.\windows\Server_manager.ps1
```

On first run, the script only sets up SteamCMD. It does not ask for Steam credentials during startup.

When you choose `Update server` or `Update mods`, the manager will:

- use the saved SteamCMD account if one is already configured
- otherwise prompt you to `Use account once` or `Save account securely`
- let you clear the saved SteamCMD account from `Configure SteamCMD account`

If SteamCMD sign-in fails, the manager shows guided retry options and marks the main menu status as `Last sign-in failed` until the login is corrected.

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
.\windows\Server_manager.ps1
```

Update the experimental server:

```powershell
.\windows\Server_manager.ps1 -update server -app exp
```

Update both server and mods and start with the configured `launchParameters` value from `windows/server-manager.config.json`:

```powershell
.\windows\Server_manager.ps1 -u all -s start -lp user
```

Stop tracked DayZ server processes started by this script:

```powershell
.\windows\Server_manager.ps1 -s stop
```

Show help for a specific parameter:

```powershell
Get-Help .\windows\Server_manager.ps1 -Parameter update
```

## Mod Management

Use the `Manage mods` menu to:

- List client mods
- List server mods
- Add mods
- Move mods between client and server lists
- Remove mods from config

## Double-Click Launch

Use `windows/Start_Server_Manager.cmd` to run the Windows manager from File Explorer without opening a terminal first. The launcher keeps the window open after the script exits so the output remains visible.

The launcher now respects your local PowerShell execution policy. If you edit the local copy, you may need to unblock or re-sign it depending on your policy settings.

## References

- [DayZ](https://dayz.com/)
- [DayZ Official Forums](https://forums.dayz.com/forum/136-official/)
- [DayZ Wiki: Server_manager](https://community.bistudio.com/wiki/DayZ:Server_manager)
