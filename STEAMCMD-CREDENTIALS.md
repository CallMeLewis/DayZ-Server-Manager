# SteamCMD Credential Handling

This guide describes how Server\_manager.ps1 manages your SteamCMD login details. Use this information to understand how your account name and password are handled before you enter them into the script.

## Summary

- The script never asks for Steam credentials when it starts.
- One-time logins stay in memory only for your active PowerShell session.
- Saved logins are stored in the **Windows Credential Manager** (the same vault used by `cmdkey` and the built-in "Credential Manager" control panel).
- Only your Windows user account on your specific machine can read the vault entry.
- The script only interacts with your local steamcmd.exe. It never sends your details to external services.
- Credentials pass to SteamCMD through a temporary runscript file. This file is deleted the moment SteamCMD finishes.

## Credential Storage Locations

The script uses two places for credentials:

- Session-only: Stored in the `$script:steamCmdSessionCredential` variable.
- Saved: Stored in the Windows Credential Manager under the target name `DayZServerManager:SteamCmd` as a generic credential.

The script's state file (`Documents\DayZ_Server\server-manager.state.json`) no longer contains any `serverSteamAuth` block. If an older state file does still carry it, the next launch migrates it into the Credential Manager and strips the block from JSON.

You can inspect the saved entry at any time by opening `Control Panel → User Accounts → Credential Manager → Windows Credentials` and looking for the `DayZServerManager:SteamCmd` target.

## Storage Method

The script calls the native Windows Credential Manager APIs (`CredWriteW`, `CredReadW`, `CredDeleteW` from `advapi32.dll`) via P/Invoke. The credential is stored with:

- Type: `CRED_TYPE_GENERIC`
- Persistence: `CRED_PERSIST_ENTERPRISE` (per-user, survives reboots)
- Target name: `DayZServerManager:SteamCmd`

The vault itself is encrypted by the operating system and is scoped to the Windows user profile. Copying the state file or the repo to another machine (or another Windows user) does not carry the credentials across — you will be prompted to re-enter them.

## Login Options

### One-Time Login

If you select `Use account once`:

- The script asks for your name and password.
- It creates a `PSCredential` object.
- It keeps the data in `$script:steamCmdSessionCredential` and never writes it to the vault.
- The credential stays active for other updates until you close the PowerShell window.

### Saved Login

If you select `Save account securely`:

- The script asks for your name and password.
- It writes them to the Windows Credential Manager via `CredWriteW`.
- It clears any session-only data and updates your status to `Saved`.

### Failed Sign-In

If a login fails, you can:

- Re-enter account once
- Clear saved account and re-enter

The script only updates the saved vault entry if the new login succeeds.

## Passing Credentials to SteamCMD

When you update a server or mod, the script follows these steps:

1. It finds your active saved or session credential.
2. It writes a temporary file containing `login <username> <password>`.
3. It starts SteamCMD using `+runscript <path>`. This prevents your password from appearing in the command line or process logs.
4. It uses a `finally` block to delete the temporary file immediately after SteamCMD closes.

```powershell
$loginScriptPath = New-SteamCmdLoginScript -Credential $credential -Path $tempLoginScript
try {
    $proc = Invoke-SteamCmdCommand (@('+runscript', $loginScriptPath) + $Arguments)
} finally {
    Remove-Item -LiteralPath $loginScriptPath -Force -ErrorAction SilentlyContinue
}
```

SteamCMD runs through `System.Diagnostics.Process`. This allows you to see and respond to Steam Guard prompts in your terminal.

## Security Features

The script protects your password through several layers:

- **No Command-Line Exposure**: Credentials stay inside a temporary file. They never appear in Task Manager or process monitors.
- **Windows Credential Manager**: The vault is scoped to the current Windows user and machine. Data is useless on another computer or under a different Windows user.
- **Automatic Cleanup**: The script ensures the temporary login file is deleted even if an error occurs.
- **Parameter Validation**: The script checks server launch parameters against an allowlist to prevent malicious commands.
- **Signature Checks**: The script verifies Valve's Authenticode signature on steamcmd.exe before running it.

Note that your password exists in plaintext briefly while building the runscript file and while SteamCMD is active.

## Prohibited Actions

The script is programmed to avoid the following:

- Uploading credentials to GitHub or any cloud service.
- Sending data to custom APIs or third-party backends.
- Storing passwords as plain text in JSON.
- Saving one-time logins to your disk.

The credentials only go to your local steamcmd.exe.

## Removing Credentials

The `Clear-SteamCmdCredential` function performs a full cleanup:

- It wipes the session credential from memory.
- It deletes the `DayZServerManager:SteamCmd` entry from the Windows Credential Manager.
- It removes any legacy `serverSteamAuth` block still present in the state file.
- It resets the login failure markers.

You can also delete the vault entry manually via `Control Panel → Credential Manager → Windows Credentials → DayZServerManager:SteamCmd → Remove` or from an elevated prompt with `cmdkey /delete:DayZServerManager:SteamCmd`.

## Migration From DPAPI-Encrypted State Files

Older versions of the script stored credentials as DPAPI blobs inside `server-manager.state.json` under `serverSteamAuth.usernameBlob` / `serverSteamAuth.passwordBlob`. On first launch after upgrading:

1. The script reads the legacy blobs.
2. It decrypts them via `ConvertTo-SecureString` (DPAPI) — or, for very old installs, Base64-decodes the username blob.
3. It writes both values into the Windows Credential Manager via `CredWriteW`.
4. It strips `serverSteamAuth` from `server-manager.state.json` and saves the file.

If the blobs are unreadable (corrupted, or from a different Windows user), the block is left alone so you can retry later, and the script prompts for fresh credentials. No data is lost in this path.

If you downgrade to an older release, the vault entry is not automatically moved back into `state.json`; the old release will simply prompt for credentials again.

## Security Boundaries

This script is a tool for local administrators. It is not a hardened vault. You must assume credentials are visible to:

- The Windows user running the script.
- Any person or software with admin rights on your machine.
- Malware or keyloggers already on your system.

If these risks concern you, do not use the save feature. Use a dedicated Steam account that only has access to the DayZ server and Workshop files.

## Code Reference

You can verify these security steps by reviewing these functions in `Server_manager.ps1`:

- `Add-CredentialVaultTypes`
- `Write-CredentialVault`
- `Read-CredentialVault`
- `Remove-CredentialVault`
- `Save-SteamCmdCredential`
- `Get-SavedSteamCmdCredential`
- `Clear-SteamCmdCredential`
- `New-SteamCmdLoginScript`
- `Prompt-SteamCmdCredential`
- `Resolve-SteamCmdDownloadCredential`
- `Invoke-SteamCmdCommand`
- `Invoke-SteamCmdAuthenticatedOperation`
- `Test-SafeLaunchParameters`
