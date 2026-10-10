$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$session=Join-Path $PSScriptRoot ('output\reports_' + [guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $session
Set-Content -LiteralPath (Join-Path $session 'supervisor.lock') -Value ''
Set-Content -LiteralPath (Join-Path $session 'status.json') -Value '{"state":"stopped"}'
Set-Content -LiteralPath (Join-Path $session 'curriculum_state.json') -Value '{"stage_index":3}'
Set-Content -LiteralPath (Join-Path $session 'reward_history.png') -Value 'image fixture'
Set-Content -LiteralPath (Join-Path $session 'reward_history.csv') -Value 'csv fixture'
$legacy=Join-Path $session 'legacy.json'
@{session_id=(Split-Path $session -Leaf);machine='lab'} | ConvertTo-Json | Set-Content -LiteralPath $legacy
$tool=Join-Path $root 'organize_training_reports.ps1'
$before=(Get-FileHash -LiteralPath (Join-Path $session 'curriculum_state.json')).Hash
& $tool -SessionPath $session -LegacyReportPath $legacy
& $tool -SessionPath $session -LegacyReportPath $legacy
foreach ($name in @('reward_history.png','reward_history.csv')) {
    if ((Get-FileHash -LiteralPath (Join-Path $session $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $session "reports\$name")).Hash) { throw 'Copy mismatch.' }
}
if ($before -ne (Get-FileHash -LiteralPath (Join-Path $session 'curriculum_state.json')).Hash) { throw 'State changed.' }
Set-Content -LiteralPath (Join-Path $session 'reports\reward_history.png') -Value 'different'
$rejected=$false
try { & $tool -SessionPath $session -LegacyReportPath $legacy } catch { $rejected=$true }
if (-not $rejected) { throw 'Must refuse differing destination.' }
Set-Content -LiteralPath (Join-Path $session 'status.json') -Value '{"state":"running"}'
$rejected=$false
try { & $tool -SessionPath $session -LegacyReportPath $legacy } catch { $rejected=$true }
if (-not $rejected) { throw 'Must refuse running experiment.' }
Write-Output 'PASS report organization: originals/state preserved, idempotent, conflicts and running refused.'
