param([Parameter(Mandatory=$true)][string]$ConfigFile)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'checkpoint_watchdog.ps1')
. (Join-Path $PSScriptRoot 'checkpoint_worker_diagnostics.ps1')
$utf8 = [Text.UTF8Encoding]::new($false)
$initial = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
$sessionDir = [IO.Path]::GetFullPath($initial.sessionDir)
$scriptDir = [IO.Path]::GetFullPath($initial.scriptDir)
$matlabExe = [string]$initial.matlabExe
$stopFile = Join-Path $sessionDir 'STOP'
$logFile = Join-Path $sessionDir 'supervisor.log'
$statusFile = Join-Path $sessionDir 'status.json'
$owned = @{}
$child = $null
$attempt = 0
$lock = $null
$workerIndex = 0
$previousTarget = 0
$attemptDir = $null
$diagnosticDir = Join-Path (Join-Path $scriptDir 'training_diagnostics') ([IO.Path]::GetFileName($sessionDir))
if ($null -ne $initial.diagnosticRoot) {
    $diagnosticDir = Join-Path ([string]$initial.diagnosticRoot) ([IO.Path]::GetFileName($sessionDir))
}
if ($null -ne $initial.diagnosticDir) {
    $diagnosticDir = [string]$initial.diagnosticDir
}

function Update-WorkerDiagnostics {
    $readyPath = Join-Path $attemptDir 'pool_ready.json'
    if (Test-Path -LiteralPath $readyPath) {
        $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
        $script:actualWorkers = [int]$ready.actualWorkers
        $script:startupComplete = $true
    }
    Save-EpisodeWorkers -StdoutPath (Join-Path $attemptDir 'stdout.log') `
        -CsvPath (Join-Path $diagnosticDir 'episode_workers.csv') -Attempt $attempt `
        -Target $targetWorkers -Actual $actualWorkers -Seen $seenEpisodes
}

function Archive-Attempt {
    if (-not $attemptDir -or -not (Test-Path -LiteralPath $attemptDir)) { return }
    $archive = Join-Path $diagnosticDir ([IO.Path]::GetFileName($attemptDir))
    $null = New-Item -ItemType Directory -Path $archive -Force
    Get-ChildItem -LiteralPath $attemptDir -File | Where-Object { $_.Extension -in @('.log','.json') } |
        Copy-Item -Destination $archive -Force
    foreach ($name in @('supervisor.log','control.json','status.json')) {
        $path = Join-Path $sessionDir $name
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $diagnosticDir -Force }
    }
}

function Write-Log([string]$message) {
    [IO.File]::AppendAllText($logFile, ('{0:u} {1}{2}' -f [DateTime]::Now,$message,[Environment]::NewLine), $utf8)
}
function Write-Status([string]$state, [string]$message) {
    $value = @{state=$state; message=$message; attempt=$attempt; updated=[DateTime]::Now.ToString('o')}
    [IO.File]::WriteAllText($statusFile, ($value | ConvertTo-Json), $utf8)
    Write-Log "$state : $message"
}
function Get-Candidates {
    # Search ONLY this supervisor session; never pick another experiment's agent.
    $files = @(Get-ChildItem -LiteralPath $sessionDir -Recurse -File -Filter '*.mat' |
        Where-Object { ($_.Name -eq 'Agent_Final.mat' -or $_.Name -match '^Agent_?\d+\.mat$') -and
            $_.FullName.Substring($sessionDir.Length) -notmatch '[\\/]runs[\\/]' } |
        Sort-Object LastWriteTimeUtc -Descending)
    $paths = @($files | ForEach-Object { $_.FullName })
    if (-not [string]::IsNullOrWhiteSpace([string]$initial.resumeAgentFile)) {
        $paths += [string]$initial.resumeAgentFile
    }
    return $paths
}
function Remember-Process([int]$taskPid) {
    if (-not $owned.ContainsKey($taskPid)) {
        try {
            $proc = Get-Process -Id $taskPid -ErrorAction Stop
            $owned[$taskPid] = $proc.StartTime.ToUniversalTime().Ticks
        } catch { }
    }
}
function Remember-Descendants {
    $inventory = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    do {
        $added = $false
        foreach ($entry in $inventory) {
            $parentKey = [int]$entry.ParentProcessId
            $childKey = [int]$entry.ProcessId
            if ($owned.ContainsKey($parentKey) -and -not $owned.ContainsKey($childKey)) {
                # Only attribute new children to a still-verifiable parent.
                # If it has already exited, leave unobserved orphans alone.
                try {
                    $parentProcess = Get-Process -Id $parentKey -ErrorAction Stop
                    if ($parentProcess.StartTime.ToUniversalTime().Ticks -ne $owned[$parentKey]) { continue }
                } catch { continue }
                if ($entry.CreationDate.ToUniversalTime().Ticks -ge $owned[$parentKey]) {
                    Remember-Process $childKey
                    if ($owned.ContainsKey($childKey)) { $added = $true }
                }
            }
        }
    } while ($added)
    if ($attemptDir) {
        $snapshot = @($inventory | Where-Object { $owned.ContainsKey([int]$_.ProcessId) } |
            Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate)
        if ($snapshot.Count -gt 0) {
            [IO.File]::WriteAllText((Join-Path $attemptDir 'processes.json'), (ConvertTo-Json -InputObject $snapshot -Depth 4), $utf8)
        }
    }
}
function Stop-OwnedProcesses {
    foreach ($taskPid in @($owned.Keys)) {
        try {
            $proc = Get-Process -Id $taskPid -ErrorAction Stop
            if ($proc.StartTime.ToUniversalTime().Ticks -eq $owned[$taskPid]) {
                Stop-Process -Id $taskPid -Force -ErrorAction Stop
                $proc.WaitForExit(10000) | Out-Null
            }
        } catch { }
    }
    foreach ($taskPid in @($owned.Keys)) {
        $proc = Get-Process -Id $taskPid -ErrorAction SilentlyContinue
        if ($null -ne $proc -and $proc.StartTime.ToUniversalTime().Ticks -eq $owned[$taskPid]) {
            throw "Owned process $taskPid is still alive; refusing to start a replacement pool."
        }
        $owned.Remove($taskPid)
    }
}
try {
    $lock = [IO.File]::Open((Join-Path $sessionDir 'supervisor.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $null = New-Item -ItemType Directory -Path $diagnosticDir -Force
    if (-not (Test-Path -LiteralPath $matlabExe -PathType Leaf)) { throw 'Configured MATLAB executable not found.' }
    foreach ($directory in @(Get-ChildItem -LiteralPath $sessionDir -Directory)) {
        if ($directory.Name -match '^attempt_(\d+)$') { $attempt = [Math]::Max($attempt,[int]$Matches[1]) }
    }
    $launched = 0
    $noProgressFailures = 0
    while ($true) {
        if (Test-Path -LiteralPath $stopFile) { Write-Status 'stopped' 'STOP requested.'; break }
        $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
        # Defaults also support control.json written by older launchers.
        $startupTimeout = 600
        $stallTimeout = 1800
        $licenseDelay = 60
        if ($null -ne $cfg.startupTimeoutSeconds) { $startupTimeout = [double]$cfg.startupTimeoutSeconds }
        if ($null -ne $cfg.stallTimeoutSeconds) { $stallTimeout = [double]$cfg.stallTimeoutSeconds }
        if ($null -ne $cfg.licenseRetryDelaySeconds) { $licenseDelay = [double]$cfg.licenseRetryDelaySeconds }
        foreach ($timeout in @($startupTimeout,$stallTimeout,$licenseDelay)) {
            if ([double]::IsNaN($timeout) -or [double]::IsInfinity($timeout) -or $timeout -lt 0) { throw 'Watchdog timeouts must be finite, nonnegative seconds.' }
        }
        foreach ($key in @('numWorkers','checkpointEvery','episodesPerProcess','averageWindow')) {
            if ([double]$cfg.$key -lt 1 -or [double]$cfg.$key -ne [int]$cfg.$key) { throw "Invalid positive integer: $key" }
        }
        $targetWorkers = [int]$cfg.numWorkers
        $minimumWorkers = 1
        if ($null -ne $cfg.minWorkers) {
            $minimum = [double]$cfg.minWorkers
            if ([double]::IsNaN($minimum) -or [double]::IsInfinity($minimum) -or
                $minimum -lt 1 -or $minimum -gt $targetWorkers -or $minimum -ne [Math]::Floor($minimum)) {
                throw 'minWorkers must be an integer between 1 and numWorkers.'
            }
            $minimumWorkers = [int]$minimum
        }
        $fallback = @(4,2)
        if ($null -ne $cfg.fallbackWorkers) { $fallback = @($cfg.fallbackWorkers) }
        $workerPlan = @(Get-WorkerPlan $targetWorkers $fallback | Where-Object { $_ -ge $minimumWorkers })
        if ($previousTarget -ne $targetWorkers -or $workerIndex -ge $workerPlan.Count) { $workerIndex = 0 }
        $previousTarget = $targetWorkers
        $requestedWorkers = $workerPlan[$workerIndex]
        if ($cfg.episodesPerProcess -lt $cfg.averageWindow -or $cfg.episodesPerProcess -lt $cfg.checkpointEvery) {
            throw 'episodesPerProcess must cover both the averaging window and checkpoint interval.'
        }
        if ($cfg.maxAttempts -gt 0 -and $launched -ge $cfg.maxAttempts) {
            Write-Status 'paused' 'Configured maximum attempts reached; checkpoints retained.'; break
        }
        $attempt++
        $launched++
        $attemptDir = Join-Path $sessionDir ('attempt_{0:D5}' -f $attempt)
        if (Test-Path -LiteralPath $attemptDir) { throw 'Attempt directory already exists; start a new session to avoid overwriting.' }
        New-Item -ItemType Directory -Path $attemptDir | Out-Null
        $candidates = @(Get-Candidates)
        $beforeNewest = if ($candidates.Count) { $candidates[0] } else { '' }
        $payload = @{attempt=$attempt; attemptDir=$attemptDir; scriptDir=$scriptDir; sessionDir=$sessionDir;
            resumeCandidates=$candidates; numWorkers=$requestedWorkers; minWorkers=$minimumWorkers; targetWorkers=$targetWorkers; checkpointEvery=$cfg.checkpointEvery;
            episodesPerProcess=$cfg.episodesPerProcess; targetReward=$cfg.targetReward;
            averageWindow=$cfg.averageWindow; trainingDevice=$cfg.trainingDevice}
        if ($null -ne $cfg.modularRoot) {
            $payload.modularRoot = [string]$cfg.modularRoot
        }
        if ($null -ne $cfg.curriculumEnabled) { $payload.curriculumEnabled = [bool]$cfg.curriculumEnabled }
        $attemptConfig = Join-Path $attemptDir 'attempt.json'
        [IO.File]::WriteAllText($attemptConfig, ($payload | ConvertTo-Json -Depth 5), $utf8)
        $expression = "addpath('$($scriptDir.Replace("'","''"))'); checkpoint_attempt('$($attemptConfig.Replace("'","''"))');"
        $arguments = '-batch "' + $expression + '"'
        Write-Status 'running' "Starting attempt $attempt with $minimumWorkers..$requestedWorkers workers (target=$targetWorkers); resume=$beforeNewest"
        $child = Start-Process -FilePath $matlabExe -ArgumentList $arguments -WorkingDirectory $scriptDir `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $attemptDir 'stdout.log') `
            -RedirectStandardError (Join-Path $attemptDir 'stderr.log')
        $null = $child.Handle # Retain the handle so ExitCode remains readable.
        Remember-Process $child.Id
        $startedUtc = [DateTime]::UtcNow
        $lastActivityUtc = $startedUtc
        $logSignature = ''
        $startupComplete = $false
        $actualWorkers = 0
        $seenEpisodes = [Collections.Generic.HashSet[int]]::new()
        $restartReason = ''
        while (-not $child.HasExited) {
            Remember-Descendants
            Update-WorkerDiagnostics
            if (Test-Path -LiteralPath $stopFile) {
                Stop-OwnedProcesses
                Write-Status 'stopped' 'Active attempt terminated by STOP; completed checkpoints retained.'
                return
            }
            $tails = @()
            $signatures = @()
            foreach ($name in @('stdout.log','stderr.log')) {
                $path = Join-Path $attemptDir $name
                if (Test-Path -LiteralPath $path) {
                    $info = Get-Item -LiteralPath $path
                    $signatures += "$name/$($info.Length)/$($info.LastWriteTimeUtc.Ticks)"
                    $tails += @(Get-Content -LiteralPath $path -Tail 80 -ErrorAction SilentlyContinue)
                }
            }
            $signature = $signatures -join ';'
            if ($signature -ne $logSignature) { $lastActivityUtc = [DateTime]::UtcNow; $logSignature = $signature }
            $logTail = $tails -join "`n"
            if ($logTail -match '(?im)(Connected to parallel pool with\s+\d+\s+workers|^\s*Episode:\s*\d+\s*/)') {
                $startupComplete = $true
            }
            $nowUtc = [DateTime]::UtcNow
            $restartReason = Get-CheckpointWatchdogReason -LogTail $logTail -StartupComplete $startupComplete `
                -ElapsedSeconds ($nowUtc-$startedUtc).TotalSeconds -IdleSeconds ($nowUtc-$lastActivityUtc).TotalSeconds `
                -StartupTimeoutSeconds $startupTimeout -StallTimeoutSeconds $stallTimeout
            if ($restartReason) {
                Write-Status 'restarting' "Watchdog: $restartReason. Terminating this attempt before checkpoint recovery."
                Stop-OwnedProcesses
                if (-not $child.WaitForExit(10000)) { throw 'Could not terminate stalled MATLAB; refusing to launch another copy.' }
                break
            }
            Start-Sleep -Seconds 5
            $child.Refresh()
        }
        $child.WaitForExit()
        $exitCode = $child.ExitCode
        Update-WorkerDiagnostics
        if (-not $restartReason) {
            # Fast startup failures may exit between polls; still apply license cooldown.
            $endedTail = @()
            foreach ($name in @('stdout.log','stderr.log')) {
                $endedTail += @(Get-Content -LiteralPath (Join-Path $attemptDir $name) -Tail 80 -ErrorAction SilentlyContinue)
            }
            $restartReason = Get-CheckpointWatchdogReason -LogTail ($endedTail -join "`n") `
                -StartupComplete $true -ElapsedSeconds 0 -IdleSeconds 0 -StartupTimeoutSeconds 0 -StallTimeoutSeconds 0
        }
        # Native crashes may leave workers alive. Touch only verified descendants.
        Remember-Descendants
        Stop-OwnedProcesses
        $startingPath = Join-Path $attemptDir 'pool_starting.json'
        $startupFailed = (-not $startupComplete -and (Test-Path -LiteralPath $startingPath))
        $reason = $restartReason
        if (-not $reason) {
            if ($startupFailed) { $reason = 'pool_start_failed' }
            elseif ($exitCode -eq 0) { $reason = 'normal_exit' }
            else { $reason = 'matlab_error' }
        }
        [pscustomobject]@{Attempt=$attempt; TargetWorkers=$targetWorkers; RequestedWorkers=$requestedWorkers;
            ActualWorkers=$actualWorkers; PoolReady=$startupComplete; Reason=$reason; ExitCode=$exitCode;
            Started=$startedUtc.ToString('o'); Ended=[DateTime]::UtcNow.ToString('o');
            DurationSeconds=[Math]::Round(([DateTime]::UtcNow-$startedUtc).TotalSeconds,1)} |
            Export-Csv -LiteralPath (Join-Path $diagnosticDir 'worker_attempts.csv') -Append -NoTypeInformation -Encoding UTF8
        Archive-Attempt
        $nextIndex = Get-NextWorkerIndex $workerIndex $workerPlan.Count $startupComplete $startupFailed
        $hasFallback = $nextIndex -gt $workerIndex
        $workerIndex = $nextIndex
        $resultFile = Join-Path $attemptDir 'result.json'
        $result = $null
        if (Test-Path -LiteralPath $resultFile) { $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json }
        if ($exitCode -eq 0 -and $null -ne $result -and $result.pause) {
            if ($result.pauseReason) {
                Write-Status 'paused' "Training guard: $($result.pauseReason); saved progress retained, no automatic rollback."
            } else {
                Write-Status 'paused' "Curriculum stage $($result.stageId) reached its episode budget without passing; saved progress retained."
            }
            break
        }
        if ($exitCode -eq 0 -and $null -ne $result -and $result.success) {
            if (-not (Test-Path -LiteralPath $result.successAgent -PathType Leaf)) {
                throw 'Attempt reported success but Agent_Success.mat is missing.'
            }
            # Publish a convenient session-level copy only after the copy completes.
            $successAgent = Join-Path $sessionDir 'Agent_Success.mat'
            $successTemporary = Join-Path $sessionDir 'Agent_Success.pending.mat'
            if ([IO.Path]::GetFullPath($result.successAgent) -ne [IO.Path]::GetFullPath($successAgent)) {
                Copy-Item -LiteralPath $result.successAgent -Destination $successTemporary -ErrorAction Stop
                Move-Item -LiteralPath $successTemporary -Destination $successAgent -ErrorAction Stop
            }
            $provenance = @{attempt=$attempt; averageReward=$result.averageReward;
                sourceAgent=$result.successAgent; successAgent=$successAgent; completed=[DateTime]::Now.ToString('o')}
            [IO.File]::WriteAllText((Join-Path $sessionDir 'success.json'), ($provenance | ConvertTo-Json), $utf8)
            if ($result.curriculumDecision -eq 'complete') {
                Write-Status 'success' "Curriculum completed: reason=$($result.curriculumReason); agent=$successAgent"
            } else {
                Write-Status 'success' "Target met: average reward=$($result.averageReward); agent=$successAgent"
            }
            break
        }
        $afterCandidates = @(Get-Candidates)
        $afterNewest = if ($afterCandidates.Count) { $afterCandidates[0] } else { '' }
        if (($exitCode -eq 0 -and $null -ne $result) -or $afterNewest -ne $beforeNewest) {
            $noProgressFailures = 0
        } else { $noProgressFailures++ }
        if (-not $hasFallback -and $cfg.maxNoProgressFailures -gt 0 -and $noProgressFailures -ge $cfg.maxNoProgressFailures) {
            Write-Status 'paused' "Failed $noProgressFailures times without a new checkpoint. Inspect latest stdout/stderr; refusing an endless identical failure loop."
            break
        }
        Write-Status 'retrying' "Attempt exited ($exitCode); reason=$reason; next workers=$($workerPlan[$workerIndex]) (target=$targetWorkers). Restarting from newest readable checkpoint; no-progress failures=$noProgressFailures."
        $delay = [int]$cfg.retryDelaySeconds
        if ($restartReason -eq 'license_error') { $delay = [Math]::Max($delay,[int]$licenseDelay) }
        for ($remaining = $delay; $remaining -gt 0; $remaining--) {
            if (Test-Path -LiteralPath $stopFile) { break }
            Start-Sleep -Seconds 1
        }
    }
} catch {
    Write-Status 'error' $_.Exception.Message
    throw
} finally {
    Stop-OwnedProcesses
    if ($null -ne $lock -and $attemptDir) {
        try { Update-WorkerDiagnostics; Archive-Attempt } catch { Write-Warning "Diagnostic archive: $_" }
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
