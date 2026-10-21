# 全新 SAC 單程序試跑（500 回合）

使用者已選擇先以單程序 SAC 試跑。新 agent、新 replay；同一份 spatial_v2 八階段與過關門檻。CPU、無 worker pool、每100回合checkpoint、每attempt最多500回合、首次只啟動1個attempt。這是執行配方變更，不是舊組續訓，也不是收斂保證。

## 1. 遠端 PowerShell：舊組已停止才同步

目前舊組仍在跑時，不執行 pull。以下檢查不會終止程序；狀態或排他鎖不符會中止。若同一副本另有其他訓練，也必須先正常結束再更新 runtime。

```powershell
$ErrorActionPreference = 'Stop'
$root = 'D:\daniel\ModularTraining'
$oldRun = Join-Path $root 'experiments\sac_spatial_v2\runs\20261020_201931_tpad1142e4_44c3_4019_a786_72e4faa3b614'
$state = Get-Content -LiteralPath (Join-Path $oldRun 'status.json') -Raw | ConvertFrom-Json
if ($state.state -ne 'paused') { throw "舊組尚未正常暫停：$($state.state)。請稍後再執行。" }
$lock = [IO.File]::Open((Join-Path $oldRun 'supervisor.lock'), 'Open', 'ReadWrite', 'None')
$lock.Dispose()
Set-Location -LiteralPath $root
git status --short
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗；保留本機修改，不要 reset 或 clean。' }
```

## 2. 同一 PowerShell：準備一次，留下新 run 路徑

路徑收據存在時拒絕再建，避免重複執行產生多組。若出錯，先檢查訊息，不要刪收據或反覆重建。

```powershell
$receipt = Join-Path $root 'artifacts\sac-serial-500-run.txt'
if (Test-Path -LiteralPath $receipt) { throw "已準備過，請使用既有路徑：$receipt" }
& 'C:\Program Files\MATLAB\R2024b\bin\matlab.exe' -batch "addpath(pwd); info=trainingtools.prepare_sac_trial(); receipt=fullfile(pwd,'artifacts','sac-serial-500-run.txt'); assert(~isfile(receipt)); if ~isfolder(fileparts(receipt)),mkdir(fileparts(receipt));end; fid=fopen(receipt,'w','n','UTF-8'); assert(fid~=-1); fprintf(fid,'%s',info.sessionDir); fclose(fid);"
if ($LASTEXITCODE -ne 0) { throw '準備未完成；請保留輸出供核對。' }
$newRun = (Get-Content -LiteralPath $receipt -Raw).Trim()
Get-Content -LiteralPath (Join-Path $newRun 'control.json')
```

應看到 executionMode=serial、trainingDevice=cpu、episodesPerProcess=500、checkpointEvery=100、maxAttempts=1。numWorkers=1是入口相容值，serial不建立pool。此步不啟動訓練。

## 3. 啟動已準備的全新 run（只執行一次）

```powershell
$state = Get-Content -LiteralPath (Join-Path $oldRun 'status.json') -Raw | ConvertFrom-Json
if ($state.state -ne 'paused') { throw '舊組狀態已改變，停止啟動。' }
$newRun = (Get-Content -LiteralPath $receipt -Raw).Trim()
if (@(Get-ChildItem -LiteralPath $newRun -Directory -Filter 'attempt_*').Count -gt 0) {
    throw '新組已經啟動過；不要再次執行啟動指令。'
}
& 'C:\Program Files\MATLAB\R2024b\bin\matlab.exe' -batch "addpath(pwd); runPath=strtrim(fileread(fullfile(pwd,'artifacts','sac-serial-500-run.txt'))); c=jsondecode(fileread(fullfile(runPath,'control.json'))); assert(strcmp(c.executionMode,'serial') && strcmp(c.trainingDevice,'cpu') && c.episodesPerProcess==500 && c.maxAttempts==1); retry(resume=runPath,start=true);"
if ($LASTEXITCODE -ne 0) { throw '啟動失敗；請保留輸出。' }
```

此處 resume 只是啟動已準備的同一資料夾；新資料夾沒有 checkpoint，因此建立全新 agent，不讀舊組模型。預設一段結束後暫停；若課程條件或guard要求，可早於500結束。

## 4. 查看進度

```powershell
$newRun = (Get-Content -LiteralPath $receipt -Raw).Trim()
Get-Content -LiteralPath (Join-Path $newRun 'status.json')
$latest = Get-ChildItem -LiteralPath $newRun -Directory -Filter 'attempt_*' | Sort-Object Name | Select-Object -Last 1
if ($latest) { Get-Content -LiteralPath (Join-Path $latest.FullName 'stdout.log') -Tail 12 }
```

看到 `Serial training ready: no worker pool; device=cpu` 才代表本段使用新路徑。不要因GPU閒置判斷錯誤：這份配方明確使用CPU。

初始化仍有 MATLAB 啟動、環境與 Simulink 準備、初始agent存檔等成本。舊續訓還會重複載入包含replay的checkpoint；本次不宣稱已消除所有初始化成本。診斷見[程式稽核](../records/sac-code-review-2026-10-21.md)及[有限測試](../records/sac-local-probe-2026-10-21.md)。不要修改舊run快照、刪pause鎖或把六worker舊組當作新配方續接。
