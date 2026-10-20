# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 日誌解析測試：以補空白及未補空白的 episode 列驗證 worker CSV 格式及去重。
# 只寫與刪除 tests/output 的固定測試檔，不操作訓練程序。
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime/checkpoint_worker_diagnostics.ps1')
$folder = Join-Path $PSScriptRoot 'output'
$null = New-Item -ItemType Directory -Path $folder -Force
$log = Join-Path $folder 'episode-format.log'
$csv = Join-Path $folder 'episode-format.csv'
if (Test-Path -LiteralPath $csv) { Remove-Item -LiteralPath $csv }
[IO.File]::WriteAllText($log,"Episode:   1/  1 | Episode reward: 284.73 | Episode Q0: 0.00`nEpisode: 1001/2000 | Episode reward: 100 | Episode Q0: 1`n")
$seen = [Collections.Generic.HashSet[int]]::new()
Save-EpisodeWorkers $log $csv 1 6 4 $seen
Save-EpisodeWorkers $log $csv 1 6 4 $seen
$rows = @(Import-Csv -LiteralPath $csv)
if ($rows.Count -ne 2 -or ($rows.Episode -join ',') -ne '1,1001') { throw 'Padded episode parsing regression' }
Remove-Item -LiteralPath $log,$csv
Write-Output 'PASS: padded / unpadded episode formats and deduplication.'
