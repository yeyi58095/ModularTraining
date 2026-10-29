# 隨機路線 SAC：遠端操作

先確認此副本所有訓練已正常paused，才更新runtime；不要同時在兩台啟動同一run。以下遠端路徑沿用既有 `D:\daniel\ModularTraining`，若實際位置不同只改root。所有啟動均由使用者執行。

## 1. PowerShell同步

```powershell
$ErrorActionPreference = 'Stop'
$root = 'D:\daniel\ModularTraining'
Set-Location -LiteralPath $root
Get-Process MATLAB -ErrorAction SilentlyContinue | Select-Object Id,ProcessName
git status --short
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗；保留修改，不要reset/clean。' }
```

程序列表只是輔助，不能將「MATLAB開著」等同有訓練或把未顯示程序當作所有run已paused；同步前核對原run的status及supervisor.lock排他鎖。

## 2. MATLAB準備一次（不啟動）

```matlab
cd('D:\daniel\ModularTraining');
receipt = fullfile(pwd,'artifacts','sac-random-route-v1-run.txt');
assert(~isfile(receipt),'已存在收據；請讀取既有run，不要重複建立。');
trainingtools.preflight_sac_random('gpu',6);
info = trainingtools.prepare_sac_random_trial('gpu',6,28001);
if ~isfolder(fileparts(receipt)), mkdir(fileparts(receipt)); end
fid=fopen(receipt,'w','n','UTF-8'); assert(fid~=-1);
fprintf(fid,'%s',info.sessionDir); fclose(fid);
sacDir=string(info.sessionDir);
disp(jsondecode(fileread(fullfile(sacDir,'control.json'))));
```

需看到parallel、gpu、numWorkers=minWorkers=6、checkpointEvery100、episodesPerProcess500、maxAttempts1。preflight只驗證license／profile／GPU建構，不啟動pool，不是6 workers成功或性能證明。失敗先保留訊息，不反覆prepare；準備過但收據寫入失敗時，使用輸出的Session路徑恢復收據。

新run位於experiments/sac_random_route_v1/runs。不同獨立訓練種子必須新建run並使用另一個收據名稱，不改既有protocol。

## 3. MATLAB啟動第一段

```matlab
sacDir=string(strtrim(fileread(fullfile(pwd,'artifacts','sac-random-route-v1-run.txt'))));
m=jsondecode(fileread(fullfile(sacDir,'model.json')));
assert(strcmp(m.name,'sac_paper64'));
assert(isempty(dir(fullfile(sacDir,'attempt_*'))),'已啟動過，請使用接續流程。');
retry(resume=sacDir,start=true);
```

最多新增500回合，guard／課程可提早正常結束。6 workers蒐集模擬經驗，client的GPU學習；不是6張GPU。small MLP、pool啟動與資料傳輸可能限制加速。GPU無法用時會報錯，沒有宣稱自動轉CPU成功；worker不足也不默默降數量。

## 4. 查看進度

MATLAB（隨時可重複，不啟訓練）：

```matlab
sacDir=string(strtrim(fileread(fullfile(pwd,'artifacts','sac-random-route-v1-run.txt'))));
training_status(sacDir,50);
```

另一個PowerShell：

```powershell
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-random-route-v1-run.txt' -Raw).Trim()
Get-Content -LiteralPath (Join-Path $session 'status.json')
Get-Content -LiteralPath (Join-Path $session 'diagnostics\worker_attempts.csv') -Tail 5
$latest = Get-ChildItem -LiteralPath $session -Directory -Filter 'attempt_*' | Sort-Object Name | Select-Object -Last 1
if ($latest) { Get-Content -LiteralPath (Join-Path $latest.FullName 'stdout.log') -Tail 20 }
```

worker_attempts.csv要待檔案產生才讀；以ActualWorkers及本段輸出確認真的取得6個。stage進度為訓練條件暫算，不代表凍結驗收通過。

## 5. 即時圖

```powershell
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-random-route-v1-run.txt' -Raw).Trim()
$model = Get-Content -LiteralPath (Join-Path $session 'model.json') -Raw | ConvertFrom-Json
$environment = Get-Content -LiteralPath (Join-Path $session 'environment.json') -Raw | ConvertFrom-Json
if ($model.name -ne 'sac_paper64' -or $environment.id -ne 'spatial_v2') { throw '收據指向錯誤實驗。' }
python .\tools\plot_training_rewards.py "$session" --watch 6 --view
```

缺matplotlib時執行 `python -m pip install -r .\requirements-plot.txt`。繪圖視窗Ctrl+C只停止畫圖，不停止訓練。

## 6. 每段保存後評估，再接續

確認status=paused且所有MATLAB訓練程序已正常結束。在新的MATLAB工作階段讀收據後執行：

```matlab
cd('D:\daniel\ModularTraining');
sacDir=string(strtrim(fileread(fullfile(pwd,'artifacts','sac-random-route-v1-run.txt'))));
report=trainingtools.review_sac_random(sacDir,500);
```

把500換成已保存的最新Agent_Final實際回合數；首段也可能提早暫停。此入口精確評估Agent_Final的SHA，不能用同回合但不同MAT的AgentN替代。評估最多5條路線；後續stage加測無風保持能力，最多10條，每條最多3000步。純CPU sim，保留checkpoint權重。評估不是自動開訓。

達訓練門檻但尚無通過評估，curriculum_outcome會顯示frozen_evaluation_required；使用同一最新checkpoint評估後，下一次retry才在保存邊界驗證／升階。評估不過不刪鎖、不改門檻，先分析原因。不能用舊checkpoint的通過報告替新模型放行。

確認本段結果可接受、不是guard退步／預算暫停後，再接下一段：

```matlab
s=jsondecode(fileread(fullfile(sacDir,'status.json'))); assert(strcmp(s.state,'paused'));
g=fullfile(sacDir,'training_guard_state.json');
if isfile(g), gs=jsondecode(fileread(g)); assert(~gs.paused,'Guard已鎖定，請保留並分析。'); end
retry(resume=sacDir,maxAttempts=1,start=true);
```

這是同run、同agent／optimizer／replay的接續。沒有自動LR排程、回滾或選最佳分支。先不提供無限自動接段作為預設。

## 7. 正常暫停

預設maxAttempts1，每段本來就會保存後paused。如果日後明確調成多段，要在另一個PowerShell要求目前段落結束後暫停：

```powershell
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-random-route-v1-run.txt' -Raw).Trim()
$file = Join-Path $session 'control.json'
$cfg = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
$cfg.maxAttempts = 1
$tmp = "$file.pending-$([guid]::NewGuid().ToString('N'))"
$backup = "$file.replace-backup-$([guid]::NewGuid().ToString('N'))"
[IO.File]::WriteAllText($tmp, ($cfg | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
[IO.File]::Replace($tmp, $file, $backup)
if ((Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).maxAttempts -ne 1) { throw '寫入未成功。' }
```

等待status=paused／正常保存。不要用關閉MATLAB、STOP檔或刪guard state代替正常段末暫停。

## 資料位置

- attempt_*/stdout.log：訓練及stage進度；diagnostics/worker_attempts.csv：實際workers、exit與耗時。
- runs/r*/route_seeds.csv、wind_all.csv：worker本地回合路線seed／風況。
- checkpoints/、Agent_Final.mat：模型；v7保存含replay與optimizer。
- reports/evaluation_*/evaluation.json：凍結評估及同資料夾trace。
- curriculum_state.json、curriculum_outcome.json、training_guard_state.json：正式保存邊界決策。

模型與完整日誌不加入Git。交回資料可使用既有 `tools/collect_sac_evidence.ps1`，其範圍須確認包含新run，或提供新run的狀態／stdout／evaluation資料再歸檔。
