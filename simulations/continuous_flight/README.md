# Continuous flight simulation

使用者已更正：訓練用 isDone 結束 episode；此處要在 Simulink 觀察偏差過大之後的飛行，不讓 isDone 提前結束。本目錄不採先前誤解的「接 Stop Simulation」。

`FAFA_ContinuousFlight.slx` 是 spatial_v2 的獨立副本：

- RL Agent 第3輸入改接 boolean false；輸入不能留空。
- 原 isdone 子系統、判定條件與訊號仍保留，送至 `IsDoneDiagnostic`／`isDoneDiagnostic` 作觀察，不控制終止。
- StopTime=300 秒；到設定時間、使用者停止或模型錯誤時仍可結束。名稱中的 continuous 不代表無限時間。
- 不改 reward、動力學、控制器網路或既有環境／run。全部 isDone 分支均不再終止這個副本，不只距離門檻，因此必須和訓練／標準評估區分。

可在 MATLAB 專案根目錄開啟：

```matlab
open_system(fullfile(pwd,'simulations','continuous_flight','FAFA_ContinuousFlight.slx'));
```

這只開啟模型，不會自動開始模擬。RL Agent 仍使用 `Agent_Stage2`；實際按 Run 前須準備選定凍結模型與所需工作區初始條件／軌跡／風場。此副本不是完整 workspace 封裝，不會自動選擇 checkpoint。不得將本目錄當作 retry 的訓練環境或放進既有 run 取代原 SLX。

此模式跑滿 3000 步不等於通過原終止門檻，產物不得混入 compare_training_checkpoints 的標準驗收結果。來源／目的 SHA 與改動在 manifest.json。重建工具為 `trainingtools.build_continuous_flight()`，已存在目的 SLX 則拒絕覆寫。
