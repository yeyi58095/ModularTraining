# Collect the completed 1101-1500 run while its separate child can train.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$id = '20261107_002801_recovery_tpbb65eb4c'
$run = (Get-Content -LiteralPath (Join-Path $root 'artifacts/sac-wind-actor-half-1100-run.txt') -Raw).Trim()
$expected = Join-Path $root "experiments/sac_random_route_v1/runs/$id"
if ((Resolve-Path -LiteralPath $run).Path -ne (Resolve-Path -LiteralPath $expected).Path) {
    throw 'Unexpected run receipt.'
}
$lock = [IO.File]::Open((Join-Path $run 'supervisor.lock'),'Open','ReadWrite','None')
try {
    $status = Get-Content -LiteralPath (Join-Path $run 'status.json') -Raw | ConvertFrom-Json
    $outcome = Get-Content -LiteralPath (Join-Path $run 'curriculum_outcome.json') -Raw | ConvertFrom-Json
    if ($status.state -ne 'paused' -or $outcome.episodes -ne 1500) { throw 'Expected saved episode 1500 and paused state.' }
    $files = @('control.json','status.json','model.json','recovery.json','environment.json','environment',
        'model_source','curriculum.json','curriculum_state.json','curriculum_outcome.json','training_guard.json',
        'training_guard_state.json','checkpoint_storage.json','checkpoints','Agent_Final.mat')
    $files += @(Get-ChildItem -LiteralPath $run -Directory -Filter 'attempt_*' | ForEach-Object Name)
    foreach ($name in @('reports/reward_history.csv','diagnostics/worker_attempts.csv')) {
        if (Test-Path -LiteralPath (Join-Path $run $name)) { $files += $name }
    }
    $packages = Join-Path $root 'artifacts/packages'
    [IO.Directory]::CreateDirectory($packages) | Out-Null
    $zip = Join-Path $packages ("sac-actor-half-1500-{0}.zip" -f [guid]::NewGuid().ToString('N'))
    $pending = "$zip.pending.zip"
    tar -a -cf $pending -C $run @files
    if ($LASTEXITCODE) { throw 'Archive creation failed.' }
    $entries = @(tar -tf $pending)
    if ($LASTEXITCODE -or 'checkpoints/Agent1500.mat' -notin $entries) { throw 'Missing Agent1500 in archive.' }
    Move-Item -LiteralPath $pending -Destination $zip
    Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List Path,Hash
} finally {
    $lock.Dispose()
}
