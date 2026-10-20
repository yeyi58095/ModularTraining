# 第三組診斷、長 attempt 與 SAC 試驗

遠端根目錄為 `D:\daniel\ModularTraining`。第三組 PPO 已於 17200 正常保存暫停，保留 `maxAttempts=1`。使用者最新更正：遠端尚未同步完整檔案編排；先前回報只證明當時版本與部分快取整理，不代表目前全部更新。

## 1. 遠端同步與整理

PowerShell，確認沒有其他訓練使用這份 checkout。不要 reset/clean 或覆蓋本機修改。

```powershell
Set-Location -LiteralPath 'D:\daniel\ModularTraining'
$runDir = Join-Path (Get-Location) 'experiments\progressive_v2\runs\20261019_164959_tpc77cb232_0370_4212_a632_e1644201eec0'
$state = Get-Content -LiteralPath (Join-Path $runDir 'status.json') -Raw | ConvertFrom-Json
if ($state.state -ne 'paused') { throw '先保持第三組 paused。' }
$runLock = [IO.File]::Open((Join-Path $runDir 'supervisor.lock'), 'Open', 'ReadWrite', 'None')
try {
    git status --short
    if ((git branch --show-current) -ne 'main') { throw '目前不是 main，先核對分支。' }
    git pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw '更新失敗，保留本機變更並貼回錯誤。' }
} finally { $runLock.Dispose() }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\finish_workspace_layout.ps1 -SessionPath $runDir
```

確認預覽，再執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\finish_workspace_layout.ps1 -SessionPath $runDir -Apply
git status --short
git log -1 --oneline
```

三個整理工具只移動原已允許的散落檔／快取並建立 `.lnk`。不搬 run，不同步 MAT。另一台若需要已完成39300模型，依 [workspace-layout](workspace-layout.md) 的 SHA 核對下載步驟；本機成果入口已存在。

## 2. 先診斷現有 PPO

新的 MATLAB 工作階段，關閉 FAFA_Simulation，先執行：

```matlab
cd('D:\daniel\ModularTraining')
rehash
runDir=fullfile(pwd,'experiments','progressive_v2','runs', ...
    '20261019_164959_tpc77cb232_0370_4212_a632_e1644201eec0');
reviews=trainingtools.review_round3(runDir);
shadow=trainingtools.shadow_learning_review(runDir,17200);
disp(shadow.outputDir)
```

四次 CPU 純 sim：16000/17200、Stage3、seed101，各有／無探索，stdScale=1。保存 diagnostics、獨立路線距離與終止證據。它是單一固定路線診斷，不是可靠度驗收。沒有重啟、調 LR、修改門檻或覆寫模型。

判讀：
- 有／無探索都在相近位置失敗：先查路線幾何、觀測與控制能力，不由 reward 曲線推論 LR 過高。
- 無探索較好、有探索較差：進一步量測探索 std；不直接永久減半。
- 後期 checkpoint 無探索也變差：獨立 validation 確認後再做單變因 LR 子分支。
- 兩者都尚未學會：保留資料與門檻，將 SAC 作獨立新 agent 比較，不能轉換 PPO 權重續接。

`shadow_learning_review` 只重播保存歷史並寫建議，不自動模擬、調 LR、回滾或開分支。完整自動決策仍需驗證、冷卻、冪等啟動及介入預算驗收；不能將 shadow 稱為自動學習控制器。

## 3. 長 attempt 的 PPO 子分支（診斷後選用）

```matlab
child=trainingtools.prepare_recovery_training(runDir, ...
    "configs/recovery_round3_17200_long_attempt.json");
```

僅準備新分支，父 run 保持 paused。每程序最多1000、每100回合checkpoint與課程／退步檢查、額外2000回合上限；actor LR不變。guard為同階段參考reward>=1000、steps>=1400、兩個100回合窗的reward及steps同時低於參考60%才暫停。這是工程保護規則，不是根因診斷或改善保證。

若要500回合，另複製此配方改 `episodes_per_process` 為500；不要改既有 run 的快照。prepare會驗證窗口對齊。保留來源SHA、lineage與原環境。不提供同時啟動PPO和SAC的指令。

## 4. 獨立 SAC 試驗

```matlab
sac=trainingtools.prepare_sac_trial();
disp(sac.sessionDir)
```

只建立新 run。選用此試驗而非PPO子分支後，明確啟動指令為：

```matlab
retry(resume=sac.sessionDir,start=true);
```

預設一個attempt最多1000回合，階段達標可更早結束，之後暫停檢查；不承諾一次跑完整課程。新agent、同spatial_v2、同八階段門檻，uniform replay 100000、sequence length32、batch64、雙Q critic、自動熵調整。保留replay／optimizer／target保存選項；本機已驗證可學權重與replay接續，不宣稱私有optimizer逐位相同。

SAC的目的是比較資料重用與探索控制；它不是2026最新演算法，也未證明優於本專案PPO。資料來源：
[SAC原論文](https://proceedings.mlr.press/v80/haarnoja18b.html)、
[自動熵調整](https://arxiv.org/abs/1812.05905)、
[MathWorks SAC](https://www.mathworks.com/help/reinforcement-learning/ref/rl.agent.rlsacagent.html)。
相容性以本機R2024b實測為準。更長attempt減少建池次數，但改變重啟／seed節奏，不保證吞吐或學習速度提高固定倍數。

## 其他待辦的完成邊界

- 停止條件：R2024b必須在建構options時一起傳Custom與回呼。先寫回呼至AverageReward會報型別錯誤，不能照原待辦字面順序實作。
- 連續模擬：`trainingtools.simulate_continuous_flight(checkpoint,scenarioFile,stageId,seed)`，使用已保存情境與獨立模型；保留原done診斷，不能拿跑滿當標準評估通過。
- Stage8 seed902：保留原偏離案例；已有trace只能提供觀測證據，物理原因仍需重播介入比較。
- 根目錄 `ppo_lstm_fromgenimi.md` 是使用者提供的分析假設；「曲線下降必然是LR過高／熵崩潰」尚無量測支持，未覆寫或加入本次提交。
