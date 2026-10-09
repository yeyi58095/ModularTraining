# Read-only checks; never inspect or close arbitrary desktop windows.
function Get-CheckpointWatchdogReason {
    param([string]$LogTail, [bool]$StartupComplete, [double]$ElapsedSeconds,
        [double]$IdleSeconds, [double]$StartupTimeoutSeconds, [double]$StallTimeoutSeconds)
    if ($LogTail -match '(?i)(Licensing\s+Error\s*:?\s*5008|You are not licensed to use\s+R\d{4}[ab]|License checkout failed)') {
        return 'license_error'
    }
    if (-not $StartupComplete -and $StartupTimeoutSeconds -gt 0 -and $ElapsedSeconds -ge $StartupTimeoutSeconds) {
        return 'startup_timeout'
    }
    if ($StartupComplete -and $StallTimeoutSeconds -gt 0 -and $IdleSeconds -ge $StallTimeoutSeconds) {
        return 'log_stall_timeout'
    }
    return ''
}
