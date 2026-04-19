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
- Check for and install manager updates from GitHub

## Hybrid Architecture

The manager uses a balanced hybrid design:

- Windows PowerShell is the user-facing entrypoint.
- Shared cross-platform config, launch, and mod-group logic lives in the Python core under `dayz_manager/`.
- Platform-specific startup, credential handling, and process integration stay in the native wrapper.

This keeps the terminal-first workflow intact.

## New: Mod Groups

Mod groups let you save multiple named mod profiles and swap them in seconds.

- Create, edit, rename, clone, delete, or view groups from `Manage mod groups`
- Switch the active group from the main menu to instantly rewrite `-mod` and `-serverMod`
- The first run migrates your current launch parameters into a `Default` group
- Store a map (mission folder) per group; switching groups updates `template` in `serverDZ.cfg`

## New: Update Check and In-App Install

On launch, the manager checks GitHub for a newer release (3-second timeout, results cached for 6 hours, silent on failure).

- If a newer release exists, a one-time full-screen notice appears. Press Enter to dismiss.
- A persistent `* Update available: vX.Y.Z` indicator stays on the main menu until you update.
- An `Install available update` option appears on the main menu. Select it, confirm, and the manager downloads the platform-specific release zip, backs up every file it will overwrite to `.update-backup/`, and swaps in the new files. No git or unzip required.
- On success you are prompted to restart. If anything fails mid-apply the backed-up files are restored automatically.

Scripted runs (`-u`, `-s`) skip the check entirely.

## Requirements

- PowerShell 4 or newer
- Windows 10, Windows Server 2012 R2, or newer
- SteamCMD
- A Steam account that owns DayZ for server and Workshop downloads
- Python 3 on the host

The wrappers now run a dependency preflight on every launch. If Python 3 is missing, startup stops and prints the one-line install command for the detected platform package manager.

## Repository Layout

- `windows/`: Windows entrypoints and launcher
- `dayz_manager/`: shared Python backend used by the wrapper
- `python_tests/`: shared regression suite for the hybrid core and wrapper helpers
- `STEAMCMD-CREDENTIALS.md`: SteamCMD credential handling details

## Configuration

The manager uses a canonical per-user config plus a per-user state file.

### Windows Config

Stored in the current Windows user's Documents folder:

`<Documents>\DayZ_Server\server-manager.config.json`

This file contains the persistent manager configuration:

- `launchParameters`
- `mods`
- `serverMods`
- `modGroups`
- `activeGroup`

Older Windows installs stored `server-manager.config.json` next to `windows/Server_manager.ps1`. On the first upgraded run, that legacy file is copied into the canonical Documents location and renamed to `server-manager.config.json.legacy.bak`.

### Saved State

Stored in the current Windows user documents folder:

Located in the system Documents folder (supports redirected or roaming profiles):

`<Documents>\DayZ_Server\server-manager.state.json`

This file contains the current runtime state used by the manager:

- SteamCMD path
- Last SteamCMD sign-in status
- Generated launch mod strings
- Tracked DayZ server process metadata

The state file is restricted to the current Windows user via file permissions.

Saved SteamCMD account credentials (username and password) are stored in Windows Credential Manager under the current Windows user profile and are not kept in `server-manager.state.json`. Existing saved logins from older releases are migrated automatically on first launch. You can also choose a one-time account login that is kept only for the current PowerShell session.

Credentials are never passed on the SteamCMD command line. Instead, they are written to a temporary runscript file that is deleted immediately after use. See `STEAMCMD-CREDENTIALS.md` for full details.

If Steam Guard is enabled, SteamCMD may require either Steam app confirmation or an email code during sign-in. When Steam Guard uses email, SteamCMD asks for that code in the same console window after the password step.

## Config Transfer

The wrapper includes a `Config Transfer` submenu for backup and machine moves.

- `Export config` writes a portable JSON envelope with `formatVersion`, `platform`, and sanitized `config` data.
- `Import config` validates that envelope through the shared Python backend before replacing the canonical config.
- Before import overwrite, the current canonical config is backed up beside it as `.import.bak`.

Exports intentionally exclude Steam account credentials and runtime state. After import the wrapper resyncs active-group launch parameters, generated launch strings, and mission side effects.

## Usage

### Interactive Menu

```powershell
.\windows\Server_manager.ps1
```

On first run, the script only sets up SteamCMD. It does not ask for Steam credentials during startup.

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

## Examples

Open the main menu:

```powershell
.\windows\Server_manager.ps1
```

Update the experimental server:

```powershell
.\windows\Server_manager.ps1 -update server -app exp
```

Update both server and mods and start with the configured `launchParameters` value from the canonical Windows config:

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
- Add mods with a required title
- Move mods between client and server lists
- Remove mods from config

## Double-Click Launch

Use `windows/Start_Server_Manager.cmd` to run the Windows manager from File Explorer without opening a terminal first. The launcher keeps the window open after the script exits so the output remains visible.

The launcher runs `Unblock-File` on `Server_manager.ps1` before invoking it, so `RemoteSigned` execution policy no longer blocks the (unsigned) script after you download a release zip. If your policy is `AllSigned` you will still need to sign the script yourself or relax the policy.

## References

- [DayZ](https://dayz.com/)
- [DayZ Official Forums](https://forums.dayz.com/forum/136-official/)
- [DayZ Wiki: Server_manager](https://community.bistudio.com/wiki/DayZ:Server_manager)
