# SteamCMD Credential Handling

This guide describes how Server\_manager.ps1 manages your SteamCMD login details. Use this information to understand how your account name and password are handled before you enter them into the script.

## Summary

- The script never asks for Steam credentials when it starts.
- One-time logins stay in memory only for your active PowerShell session.
- Saved logins are stored in a state file within your system Documents folder.
- The script encrypts your username and password using Windows DPAPI. Only your Windows user account on your specific machine can decrypt them.
- File permissions restrict the state file so only your Windows user can access it.
- The script only interacts with your local steamcmd.exe. It never sends your details to external services.
- Credentials pass to SteamCMD through a temporary runscript file. This file is deleted the moment SteamCMD finishes.

## Credential Storage Locations

The script uses two places for credentials:

- Session-only: Stored in the `$script:steamCmdSessionCredential` variable.
- Saved: Stored in `Documents\DayZ_Server\server-manager.state.json`.

The saved file uses the `serverSteamAuth` property:

```json
{
  "serverSteamAuth": {
    "usernameBlob": "...",
    "passwordBlob": "..."
  }
}
```

## Storage Methods

### Username

The `usernameBlob` contains your encrypted username. The `Protect-StateSecret` function turns the name into a `SecureString` and uses `ConvertFrom-SecureString` to create an encrypted blob. This uses Windows DPAPI to lock the data to your Windows account. If you have an older state file using Base64, the script automatically upgrades it to DPAPI encryption when you first run it.

### Password

The `passwordBlob` uses the same DPAPI encryption method:

```powershell
$secureValue = ConvertTo-SecureString $Value -AsPlainText -Force
ConvertFrom-SecureString $secureValue
```

The script relies on PowerShell's built-in commands to handle the cryptography internally.

### File Permissions

Every time the script writes to the state file, it uses `icacls` to lock it down. It removes inherited permissions and grants full control only to your Windows user.

## Login Options

### One-Time Login

If you select `Use account once`:

- The script asks for your name and password.
- It creates a `PSCredential` object.
- It keeps the data in `$script:steamCmdSessionCredential` and never writes it to your disk.
- The credential stays active for other updates until you close the PowerShell window.

### Saved Login

If you select `Save account securely`:

- The script asks for your name and password.
- It encrypts the data into `usernameBlob` and `passwordBlob` within `server-manager.state.json`.
- It applies strict file permissions to the JSON file.
- It clears any session-only data and updates your status to `Saved`.

### Failed Sign-In

If a login fails, you can:

- Re-enter account once
- Clear saved account and re-enter

The script only updates the saved JSON file if the new login succeeds.

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
- **DPAPI Encryption**: Your data is useless on another computer or under a different Windows user.
- **File Permissions**: The JSON file stays restricted to your account.
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
- It deletes the `serverSteamAuth` section from your state file.
- It resets the login failure markers.

## Security Boundaries

This script is a tool for local administrators. It is not a hardened vault. You must assume credentials are visible to:

- The Windows user running the script.
- Any person or software with admin rights on your machine.
- Malware or keyloggers already on your system.

If these risks concern you, do not use the save feature. Use a dedicated Steam account that only has access to the DayZ server and Workshop files.

## Code Reference

You can verify these security steps by reviewing these functions in `Server_manager.ps1`:

- `Protect-StateSecret`
- `Unprotect-StateSecret`
- `Convert-LegacyUsernameBlob`
- `Save-SteamCmdCredential`
- `Get-SavedSteamCmdCredential`
- `New-SteamCmdLoginScript`
- `Prompt-SteamCmdCredential`
- `Resolve-SteamCmdDownloadCredential`
- `Invoke-SteamCmdCommand`
- `Invoke-SteamCmdAuthenticatedOperation`
- `Set-PrivateFileAcl`
- `Test-SafeLaunchParameters`
