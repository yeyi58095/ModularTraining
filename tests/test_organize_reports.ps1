# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 報告整理合成測試：驗證雜湊一致、重跑、內容衝突拒絕及活動狀態拒絕。
# 只寫 tests/output fixture，確認 curriculum_state 原件不變。
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
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
$tool=Join-Path $root 'tools/organize_training_reports.ps1'
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
