$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output\pack_'+[guid]::NewGuid().ToString('N'))
foreach ($folder in @('checkpoints','runs/r000001','reports/evaluation_test','attempt_00001')) { $null=New-Item -ItemType Directory -Path (Join-Path $fixture $folder) -Force }
foreach ($file in @('supervisor.lock','checkpoints/Agent10600.mat','checkpoints/Agent10700.mat','runs/r000001/Agent_Initial.mat','runs/r000001/TrainingOptions.mat','runs/r000001/training_script_snapshot.m','reports/evaluation_test/ep10600_stage1_seed101.mat','attempt_00001/stdout.log')) { Set-Content -LiteralPath (Join-Path $fixture $file) -Value 'fixture' }
foreach ($file in @('control.json','model.json','curriculum.json','curriculum_state.json','recovery.json')) { Set-Content -LiteralPath (Join-Path $fixture $file) -Value '{}' }
Set-Content -LiteralPath (Join-Path $fixture 'status.json') -Value '{"state":"paused"}'
Set-Content -LiteralPath (Join-Path $fixture 'reports/evaluation_test/evaluation.json') -Value '{"status":"complete","results":[{"trace":"ep10600_stage1_seed101.mat"}]}'
$before=(Get-FileHash -LiteralPath (Join-Path $fixture 'checkpoints/Agent10600.mat')).Hash
$output=& (Join-Path $root 'pack_training_diagnostics.ps1') -SessionPath $fixture -EvaluationName evaluation_test
$output | Write-Output
if (-not ($output -match '^Verified ZIP:')) { throw 'No verified archive.' }
if ($before -ne (Get-FileHash -LiteralPath (Join-Path $fixture 'checkpoints/Agent10600.mat')).Hash) { throw 'Source changed.' }
Set-Content -LiteralPath (Join-Path $fixture 'status.json') -Value '{"state":"running"}'
$rejected=$false
try { & (Join-Path $root 'pack_training_diagnostics.ps1') -SessionPath $fixture -EvaluationName evaluation_test } catch { $rejected=$_.Exception.Message -match 'Stop training' }
if (-not $rejected) { throw 'Active session was not rejected.' }
Write-Output 'PASS: ZIP contents hash-verified, source preserved, active session rejected.'
