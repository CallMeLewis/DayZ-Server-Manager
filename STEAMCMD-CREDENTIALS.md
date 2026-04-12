# SteamCMD Credential Handling

This document explains how `Server_manager.ps1` handles SteamCMD credentials today.

It is written for anyone who wants to understand exactly what the script does before entering a Steam account name and password.

## Short Version

- The script does not ask for Steam credentials on startup.
- A one-time login is kept in memory only for the current PowerShell session.
- A saved login is written to `%USERPROFILE%\Documents\DayZ_Server\server-manager.state.json`.
- The saved password is not stored in plaintext in that JSON file.
- The script does not send credentials to any service of its own. It launches local `steamcmd.exe` and passes the credentials to SteamCMD.
- The password is converted back to plaintext in memory and passed to SteamCMD as `+login <user> <password>`.

## Where Credentials Live

The script uses two credential locations:

- Session-only credential: stored in the script variable `$script:steamCmdSessionCredential`
- Saved credential: stored in the state file at `%USERPROFILE%\Documents\DayZ_Server\server-manager.state.json`

The saved credential is stored under the `serverSteamAuth` property with this shape:

```json
{
  "serverSteamAuth": {
    "usernameBlob": "...",
    "passwordBlob": "..."
  }
}
```

## What Gets Stored

### Username

The username is stored in `usernameBlob`.

This is created by `Protect-StateSecret -AsPlainText`, which base64-encodes the username. That makes it safe for JSON storage, but it is not a secret-protection mechanism by itself.

### Password

The password is stored in `passwordBlob`.

This is created by:

```powershell
$secureValue = ConvertTo-SecureString $Value -AsPlainText -Force
ConvertFrom-SecureString $secureValue
```

The script does not call `System.Security.Cryptography.ProtectedData` directly. Instead, it relies on PowerShell's built-in `ConvertFrom-SecureString` and `ConvertTo-SecureString` behavior.

In practical terms, the saved password blob is intended to be recoverable by the same Windows user context that created it, through PowerShell, on that machine.

## One-Time vs Saved Login

### Use Account Once

If the user chooses `Use account once`:

- the script prompts for account name and password
- creates a `PSCredential`
- stores it only in `$script:steamCmdSessionCredential`
- does not write it to disk

That credential is available to later update operations in the same PowerShell session.

### Save Account Securely

If the user chooses `Save account securely`:

- the script prompts for account name and password
- creates a `PSCredential`
- writes `usernameBlob` and `passwordBlob` into `server-manager.state.json`
- clears any leftover session-only credential so status shows `Saved`

### Retry After Failed Sign-In

If SteamCMD sign-in fails, the retry flow offers:

- `Re-enter account once`
- `Clear saved account and re-enter`

The second path uses a temporary in-memory credential first. It is only written back to `server-manager.state.json` if the retry succeeds.

## How Credentials Reach SteamCMD

When an authenticated server or Workshop update runs, the script resolves the active credential, then builds the SteamCMD login arguments:

```powershell
@('+login', $credential.UserName, $credential.GetNetworkCredential().Password)
```

Those arguments are then converted to a single command-line string and assigned to:

```powershell
$psi.Arguments = ConvertTo-SteamCmdArgumentString $Arguments
```

SteamCMD is launched through `System.Diagnostics.Process` with inherited console handles so Steam Guard prompts can appear in the same terminal window.

## Important Security Implication

The password is not stored in plaintext on disk, but it is turned back into plaintext before SteamCMD starts.

That means:

- the password exists in process memory while the script is building the login arguments
- the password is included in the command line passed to `steamcmd.exe`
- local process-inspection tools, administrative access, or malware on the machine may be able to read it while SteamCMD is running

The script does not print the password itself, but it also is not a hardened secret vault. It is a convenience layer around local SteamCMD usage.

## What The Script Does Not Do

From the script's own code path:

- it does not upload credentials to GitHub
- it does not send credentials to a custom API or third-party backend
- it does not store the saved password as plain JSON text
- it does not persist one-time credentials to disk unless the user explicitly chooses a saved flow

The only intended downstream consumer of the credential is local `steamcmd.exe`, which then authenticates with Steam.

## Clearing Credentials

`Clear-SteamCmdCredential` does all of the following:

- clears the in-memory session credential
- removes `serverSteamAuth` from `server-manager.state.json`
- clears the `lastSteamCmdSignInFailed` marker

## Trust Boundaries

This design is reasonable for a local admin utility, but it is not equivalent to a dedicated secret manager.

You should assume the credentials are exposed to:

- the Windows user account running the script
- anything with sufficient local privilege to inspect that user's processes or memory
- any malware already present on the system

If that risk is not acceptable, do not save the credential, and consider using a dedicated Steam account with only the access required for DayZ server and Workshop downloads.

## Functions To Review

If you want to verify the implementation yourself, these are the key functions in `Server_manager.ps1`:

- `Protect-StateSecret`
- `Unprotect-StateSecret`
- `Save-SteamCmdCredential`
- `Get-SavedSteamCmdCredential`
- `Prompt-SteamCmdCredential`
- `Resolve-SteamCmdDownloadCredential`
- `Get-SteamCmdLoginArguments`
- `ConvertTo-SteamCmdArgumentString`
- `Invoke-SteamCmdCommand`
- `Invoke-SteamCmdAuthenticatedOperation`
