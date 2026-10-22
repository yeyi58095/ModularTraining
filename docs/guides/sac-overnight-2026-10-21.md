# SAC夜間接續與監看

本次接續已保存1000回合的serial CPU SAC，不重建agent。每attempt500、每100checkpoint、maxAttempts=0自動接下一段；原預算、guard、失敗與完成停止條件仍有效。不是關閉全部停止條件的continuous_training分支。

## PowerShell：paused時同步

```powershell
$ErrorActionPreference = 'Stop'
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-serial-500-run.txt' -Raw).Trim()
$state = Get-Content (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
if ($state.state -ne 'paused' -or $state.message -notlike 'Configured maximum attempts*') {
    throw '不是預期的段落上限暫停，請先核對狀態。'
}
$lock = [IO.File]::Open((Join-Path $session 'supervisor.lock'), 'Open', 'ReadWrite', 'None')
$lock.Dispose()
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗，保留檔案並貼回錯誤。' }
```

## MATLAB：啟動一次，之後用同視窗查log

```matlab
cd('D:\daniel\ModularTraining');
sacDir = string(strtrim(fileread(fullfile(pwd,'artifacts','sac-serial-500-run.txt'))));
s = jsondecode(fileread(fullfile(sacDir,'status.json')));
c = jsondecode(fileread(fullfile(sacDir,'control.json')));
assert(strcmp(s.state,'paused') && startsWith(s.message,'Configured maximum attempts'));
assert(strcmp(c.executionMode,'serial') && strcmp(c.trainingDevice,'cpu'));
assert(c.episodesPerProcess==500 && c.checkpointEvery==100);
info = retry(resume=sacDir, maxAttempts=0, fastRestart="off", start=true);
training_status(sacDir,50);
```

只執行啟動一次。之後只需重新執行 `training_status(sacDir,50)`；這是一次性讀取最新50行，不會重啟或停止訓練。首次回合應從1001開始（若已有其他接續，以實際保存進度為準）。

## 另一個PowerShell：每6秒更新曲線

```powershell
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-serial-500-run.txt' -Raw).Trim()
$model = Get-Content (Join-Path $session 'model.json') -Raw | ConvertFrom-Json
$envInfo = Get-Content (Join-Path $session 'environment.json') -Raw | ConvertFrom-Json
if ($model.algorithm -ne 'SAC' -or $envInfo.id -ne 'spatial_v2') { throw '實驗選擇不符。' }
Write-Host "繪圖實驗：$session"
python .\tools\plot_training_rewards.py "$session" --watch 6 --view
```

若缺matplotlib，先執行 `python -m pip install -r .\requirements-plot.txt`。關閉繪圖視窗或在這個繪圖PowerShell按Ctrl+C只停止繪圖。電腦需保持開機且不休眠。

## 隔天：讓目前段落保存後暫停

在另一個PowerShell操作control，不在活動訓練期間呼叫retry重新啟動：

```powershell
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-serial-500-run.txt' -Raw).Trim()
$file = Join-Path $session 'control.json'
$cfg = Get-Content $file -Raw | ConvertFrom-Json
Copy-Item -LiteralPath $file -Destination "$file.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$cfg.maxAttempts = 1
$tmp = "$file.pending-$([guid]::NewGuid().ToString('N'))"
[IO.File]::WriteAllText($tmp, ($cfg | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$replaceBackup = "$file.replace-backup-$([guid]::NewGuid().ToString('N'))"
[IO.File]::Replace($tmp, $file, $replaceBackup)
$saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
if ($saved.maxAttempts -ne 1) { throw '段末暫停設定未寫入。' }
Get-Content (Join-Path $session 'status.json')
```

這是段末暫停，不是即刻停止；稍後確認state=paused。不要用STOP檔或關閉MATLAB來代替正常保存暫停。
