$script:ServerManagerSkipAutoRun = $true
. "$PSScriptRoot\..\..\windows\Server_manager.ps1"

Describe 'Windows Credential Vault helpers' {
    BeforeEach {
        $script:vaultTestTarget = "DayZServerManagerTest:$([guid]::NewGuid())"
    }

    AfterEach {
        try { Remove-CredentialVault -Target $script:vaultTestTarget } catch { }
    }

    It 'round trips a stored username and password' {
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password 'secret-pass'

        $read = Read-CredentialVault -Target $script:vaultTestTarget

        $read.Username | Should Be 'dayz-owner'
        $read.Password | Should Be 'secret-pass'
    }

    It 'returns null when the target has no stored credential' {
        $missingTarget = "DayZServerManagerTest:$([guid]::NewGuid())"

        $read = Read-CredentialVault -Target $missingTarget

        $read | Should Be $null
    }

    It 'remove is silent when the target does not exist' {
        $missingTarget = "DayZServerManagerTest:$([guid]::NewGuid())"

        { Remove-CredentialVault -Target $missingTarget } | Should Not Throw
    }

    It 'round trips a 128-character password without truncation' {
        $longPassword = ('a' * 128)
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password $longPassword

        $read = Read-CredentialVault -Target $script:vaultTestTarget

        $read.Password | Should Be $longPassword
    }

    It 'round trips a password containing unicode characters' {
        $unicodePassword = 'p@ssw0rd-ünïcödé-🔐'
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password $unicodePassword

        $read = Read-CredentialVault -Target $script:vaultTestTarget

        $read.Password | Should Be $unicodePassword
    }

    It 'overwrites an existing credential with a new password' {
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password 'first-pass'
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password 'second-pass'

        $read = Read-CredentialVault -Target $script:vaultTestTarget

        $read.Password | Should Be 'second-pass'
    }

    It 'remove makes a previously stored credential unreadable' {
        Write-CredentialVault -Target $script:vaultTestTarget -Username 'dayz-owner' -Password 'secret-pass'
        Remove-CredentialVault -Target $script:vaultTestTarget

        $read = Read-CredentialVault -Target $script:vaultTestTarget

        $read | Should Be $null
    }
}
