param([switch]$PackageOnly)
# Run on the remote training machine. Never git pull or change existing runs.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$bundle=Join-Path $root 'artifacts/packages/sac-review-cycle-20261114'
[IO.Directory]::CreateDirectory($bundle) | Out-Null
$lock=[IO.File]::Open((Join-Path $bundle 'launcher.lock'),'OpenOrCreate','ReadWrite','None')
$failure=$null
try {
    try {
        if (-not $PackageOnly) {
            $matlab=(Get-Command matlab.exe -ErrorAction Stop).Source
            $escaped=$root.Replace("'","''")
            & $matlab -wait -logfile (Join-Path $bundle 'matlab.log') -batch "cd('$escaped'); addpath(pwd); trainingtools.run_sac_review_cycle();"
            if ($LASTEXITCODE -ne 0) { $failure="MATLAB exited with code $LASTEXITCODE. See cycle.json/cycle.log. No automatic relaunch." }
        }
    } catch { $failure=$_.Exception.Message }
    if (-not $PackageOnly) {
        $result=@{ended_at=(Get-Date).ToString('o');error=$failure;scope='Launcher only; inspect cycle.json for evaluation/training outcome'}
        [IO.File]::WriteAllText((Join-Path $bundle 'launcher_result.json'),($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    & (Join-Path $PSScriptRoot 'pack_sac_review_cycle.ps1')
    if ($failure) { throw $failure }
} finally { $lock.Dispose() }
