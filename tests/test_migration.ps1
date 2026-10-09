$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output\migration_' + [guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'session'
$null=New-Item -ItemType Directory -Path (Join-Path $source 'model_source') -Force
$null=New-Item -ItemType Directory -Path (Join-Path $source 'checkpoints') -Force
$name='test_' + [guid]::NewGuid().ToString('N')
$utf8=[Text.UTF8Encoding]::new($false)
function Put($file,$text) { [IO.File]::WriteAllText((Join-Path $source $file),$text,$utf8) }
Put 'supervisor.lock' ''
Put 'status.json' '{"state":"running","attempt":8}'
Put 'control.json' ((@{sessionDir=$source;diagnosticDir=(Join-Path $source 'diagnostics');trainingDevice='gpu';numWorkers=6}) | ConvertTo-Json)
Put 'curriculum.json' '{"schema_version":1}'
Put 'curriculum_state.json' '{"stage_index":2,"start_episode":3000}'
Put 'model.json' '{"name":"ppo_lstm128"}'
Put 'checkpoints\Agent7000.mat' 'synthetic bytes for copy/hash test, not a MATLAB checkpoint'
$tool=Join-Path $root 'migrate_training_session.ps1'
$rejected=$false
try { & $tool -SourceSession $source -CurriculumName $name } catch { $rejected=$true }
if (-not $rejected) { throw 'Running experiment must be rejected.' }
Put 'status.json' '{"state":"stopped","attempt":8}'
$lock=[IO.File]::Open((Join-Path $source 'supervisor.lock'),'Open','ReadWrite','None')
try {
    $rejected=$false
    try { & $tool -SourceSession $source -CurriculumName $name } catch { $rejected=$true }
    if (-not $rejected) { throw 'Locked experiment must be rejected.' }
} finally { $lock.Dispose() }
$before=(Get-FileHash -LiteralPath (Join-Path $source 'control.json')).Hash
& $tool -SourceSession $source -CurriculumName $name
$dest=Join-Path $root "experiments\$name\runs\session"
$cfg=Get-Content -LiteralPath (Join-Path $dest 'control.json') -Raw | ConvertFrom-Json
if ($cfg.sessionDir -ne $dest -or $cfg.diagnosticDir -ne (Join-Path $dest 'diagnostics') -or $cfg.trainingDevice -ne 'gpu' -or $cfg.numWorkers -ne 6) { throw 'Incorrect relocated configuration.' }
if ((Get-FileHash -LiteralPath (Join-Path $source 'control.json')).Hash -ne $before) { throw 'Original config changed.' }
foreach ($file in @('curriculum_state.json','checkpoints\Agent7000.mat')) {
    if ((Get-FileHash -LiteralPath (Join-Path $source $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $dest $file)).Hash) { throw 'Copy differs.' }
}
$rejected=$false
try { & $tool -SourceSession $source -CurriculumName $name } catch { $rejected=$true }
if (-not $rejected) { throw 'Existing destination must be rejected.' }
Write-Output 'PASS migration: active/locked refusal, original preserved, checkpoint/state hashes, GPU/workers retained, no overwrite.'
