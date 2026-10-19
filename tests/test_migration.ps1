# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 遷移合成測試：建立停止 run fixture，驗證完整複製、控制路徑、原件保留及拒絕活動實驗。
# 只使用 tests/output 的假資料，不續訓、不搬移真正活動 run。
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output\migration_' + [guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'session'
$null=New-Item -ItemType Directory -Path (Join-Path $source 'model_source') -Force
$null=New-Item -ItemType Directory -Path (Join-Path $source 'checkpoints') -Force
$name='test_' + [guid]::NewGuid().ToString('N')
$utf8=[Text.UTF8Encoding]::new($false)
# 在測試來源 fixture 寫入指定文字，模擬待遷移資料。
function Put($file,$text) { [IO.File]::WriteAllText((Join-Path $source $file),$text,$utf8) }
Put 'supervisor.lock' ''
Put 'status.json' '{"state":"running","attempt":8}'
Put 'control.json' ((@{sessionDir=$source;diagnosticDir=(Join-Path $source 'diagnostics');trainingDevice='gpu';numWorkers=6}) | ConvertTo-Json)
Put 'curriculum.json' '{"schema_version":1}'
Put 'curriculum_state.json' '{"stage_index":2,"start_episode":3000}'
Put 'model.json' '{"name":"ppo_lstm128"}'
Put 'checkpoints\Agent7000.mat' 'synthetic bytes for copy/hash test, not a MATLAB checkpoint'
$tool=Join-Path $root 'tools/migrate_training_session.ps1'
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
