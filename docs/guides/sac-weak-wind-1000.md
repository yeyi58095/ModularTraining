# Agent1000 弱風子實驗

原 run 暫停在 1600。從已核對 SHA 的 Agent1000 複製整個 MAT 到新 run，另記 recovery.json。子 run 從 1001 起使用原課程 Stage 2，在自己的歷史記為 experimental_scheduled_wind。沿用 GPU、同步六 workers、每 100 回合保存，最多一個 attempt、額外 500 回合，guard 可提早暫停。

遠端在停止訓練時同步程式：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗，先保留現有檔案。' }
```

在新的 R2024b MATLAB 工作階段準備。只執行一次並保存子 run 收據：

```matlab
cd('D:\daniel\ModularTraining'); addpath(pwd); rehash;
p = string(strtrim(fileread(fullfile(pwd,'artifacts','sac-random-route-v1-run.txt'))));
receipt = fullfile(pwd,'artifacts','sac-weak-wind-1000-run.txt');
assert(~isfile(receipt),'已有子 run 收據，請先查看其狀態。');
info = trainingtools.prepare_recovery_training(p,'configs/sac_weak_wind_1000.json');
child = string(info.sessionDir);
writelines(child,receipt);
disp(jsondecode(fileread(fullfile(child,'curriculum_state.json'))));
```

確認 stage_index=2、start_episode=1000 後，在同一工作階段啟動子 run：

```matlab
child = string(strtrim(fileread(receipt)));
state = jsondecode(fileread(fullfile(child,'status.json')));
assert(strcmp(state.state,'paused') && state.attempt==0 && isempty(dir(fullfile(child,'attempt_*'))));
retry(resume=child,start=true);
```

MATLAB 查進度用 `training_status(child,50)`。PowerShell 看圖：

```powershell
cd D:\daniel\ModularTraining
$child = (Get-Content -Raw -LiteralPath '.\artifacts\sac-weak-wind-1000-run.txt').Trim()
python .\tools\plot_training_rewards.py "$child" --watch 6 --view
```

保存到 1500 後以父子各自的 Agent1500 在相同新路線做凍結配對。若提早暫停，先看 guard 與最後保存點；避免用時數或僅訓練 reward 判定弱風優劣。
