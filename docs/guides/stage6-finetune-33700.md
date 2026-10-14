# 33700 分支：小學習率續訓

使用者於2026-10-14提供額外120次評估，要求本輪可繼續啟動訓練。
來源是 `20261014_000404_recovery_tp3b623159` 的 Agent33700.mat，
不是最新Agent_Final，也不是原始31600父實驗。

## 選擇依據與限制

seeds401:420、每階段20組配對，全120次皆3000步、environment_done=false，
三份報告complete、weights_unchanged=true，使用同一空間循跡SLX。

|階段|33700平均reward|41600平均reward|33700平均路徑RMS(m)|41600平均路徑RMS(m)|
|---|---:|---:|---:|---:|
|4|3049.48|3023.91|2.231|2.610|
|5|3020.17|3002.30|3.424|3.703|
|6|2943.55|2933.93|7.014|7.022|

RMS為各情境t>=10秒原始有限折線距離RMS的平均，不是全程或pooled RMS。
Stage6此區間的跨情境最大偏離33700為23.968m、41600為27.940m。
33700分數較高的配對數為20/20、17/20、14/20；Stage6距離較低只有11/20，
兩者該階段平均距離很接近。這是有限樣本候選選擇，不是證明33700全域最佳或合格。

選33700作保留起點，新分支actor LR由2.5e-5改為1.25e-5，critic及其他PPO
設定沿用；減半是待驗證的工程試驗，不是已證實學習率過大，也不保證改善。
與前段不同訓練情境、隨機序列混在一起，不能僅以曲線差異證明LR因果。
reward、環境、Stage6門檻不改。評估高分不能直接寫成課程完成。

## 啟動

PowerShell先 `git pull --ff-only`，MATLAB於專案根目錄執行：

```matlab
clear prepare_recovery_training retry
parentSession=fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261014_000404_recovery_tp3b623159");
fine=prepare_recovery_training(parentSession,"configs/recovery_33700_finetune.json");
info=retry(resume=fine.sessionDir);
disp(info.sessionDir)
```

準備程式會核對環境SHA、來源LR、checkpoint回合與停止鎖，保留權重，
建立全新run；只有retry啟動訓練。父實驗與41600保留，不覆蓋或手動解鎖guard。
硬體沿用父control（目標6 workers、允許可用數量及GPU設定，以實際log為準）。
每段100回合，新增最多3000：從33701至36700。這是新分支，終點小於舊分支41600
是正常的；圖表沿父資料只保留到33700，舊分支後續仍在原資料夾。

保留既有退步guard，但它要求reward和steps同時大幅降低，不能偵測所有循跡
品質退步。預算或guard暫停就保留暫停，再比較新分支候選與來源33700。
不自動追加預算、不承諾達到2700或課程合格。新的3000回合不在本機代跑。
