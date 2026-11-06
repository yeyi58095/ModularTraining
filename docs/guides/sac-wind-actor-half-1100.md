# 從弱風 Agent1100 開始 actor 半速候選

子 run 準備後從1101開始，最多跑400回合，保存到1500或guard提早暫停。actor LR為1.5e-4，其餘SAC沿用來源。源run需paused，精確checkpoint SHA由工具核對。

遠端PowerShell同步：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請先停止。' }
```

新的MATLAB R2024b工作階段準備：

```matlab
cd('D:\daniel\ModularTraining'); addpath(pwd); rehash;
slow = trainingtools.prepare_sac_wind_slow();
disp(jsondecode(fileread(fullfile(slow,'model.json'))));
disp(jsondecode(fileread(fullfile(slow,'control.json'))));
```

由收據啟動，禁止重複首啟：

```matlab
receipt = fullfile(pwd,'artifacts','sac-wind-actor-half-1100-run.txt');
slow = string(strtrim(fileread(receipt)));
state = jsondecode(fileread(fullfile(slow,'status.json')));
assert(strcmp(state.state,'paused') && state.attempt==0);
assert(isempty(dir(fullfile(slow,'attempt_*'))));
retry(resume=slow,start=true);
```

MATLAB監看為training_status(slow,50)。PowerShell圖表：

```powershell
cd D:\daniel\ModularTraining
$slow = (Get-Content -Raw -LiteralPath '.\artifacts\sac-wind-actor-half-1100-run.txt').Trim()
python .\tools\plot_training_rewards.py "$slow" --watch 6 --view
```

1100以前繼承祖先，1101起為actor半速分支。設定maxAttempts=1並受400回合預算保護，完成後先做凍結評估。若已存在收據，讀取其路徑與training_status查明狀態，避免重建。
