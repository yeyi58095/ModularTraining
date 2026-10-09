# Pure selection and log helpers, also exercised without running training.
function Get-WorkerPlan([int]$Target, $Fallback) {
    $valid = @($Fallback | ForEach-Object {
        if ([double]$_ -lt 1 -or [double]$_ -ne [int]$_) { throw 'fallbackWorkers must contain positive integers.' }
        if ([int]$_ -lt $Target) { [int]$_ }
    } | Sort-Object -Descending -Unique)
    return @($Target) + $valid
}

function Get-NextWorkerIndex([int]$Index, [int]$Count, [bool]$PoolReady, [bool]$StartupFailed) {
    if (-not $PoolReady -and $StartupFailed -and $Index + 1 -lt $Count) { return $Index + 1 }
    return 0
}

function Save-EpisodeWorkers([string]$StdoutPath, [string]$CsvPath, [int]$Attempt,
    [int]$Target, [int]$Actual, $Seen) {
    if ($Actual -lt 1 -or -not (Test-Path -LiteralPath $StdoutPath)) { return }
    # Start-Process keeps the redirected log open for writing while MATLAB runs.
    $stream = [IO.File]::Open($StdoutPath, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = [IO.StreamReader]::new($stream)
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    # Only completed console rows, not worker-local reset counters.
    foreach ($match in [regex]::Matches($content, '(?m)^\s*Episode:\s*(\d+)\s*/\s*\d+[^\r\n]*Episode Q0:[^\r\n]*\r?\n')) {
        $episode = [int]$match.Groups[1].Value
        if ($Seen.Contains($episode)) { continue }
        [pscustomobject]@{Attempt=$Attempt; Episode=$episode; TargetWorkers=$Target;
            ActualWorkers=$Actual; Reduced=($Actual -lt $Target)} |
            Export-Csv -LiteralPath $CsvPath -Append -NoTypeInformation -Encoding UTF8
        $null = $Seen.Add($episode)
    }
}
