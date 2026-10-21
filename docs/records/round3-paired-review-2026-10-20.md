# 第三組16000／17200配對診斷回報

來源：使用者貼回遠端 `trainingtools.review_round3` 完整輸出，後續提供四份MAT traces。Stage3 fixed_turns_calm、seed101、東／北風與turbulence均0，四次都由environment_done結束，termination_evidence均distance_threshold。

| checkpoint | exploration | reward | steps | 10秒後原路線RMS(m) | 10秒後P95(m) | 原路線最大距離(m) |
|---|---|---:|---:|---:|---:|---:|
|16000|false|1521.82199|1658|9.18391|14.26908|50.28363|
|17200|false|1532.90962|1786|12.96057|27.26182|50.25709|
|16000|true|1383.37666|1649|9.27437|18.25768|50.58900|
|17200|true|389.80152|530|14.70446|32.06572|50.35006|

無探索報告：evaluation_20261020_201111_tpfa8923ac。探索報告：evaluation_20261020_201142_tp642d53cc。皆在第三組run/reports下。

無探索也失敗，故不能將瓶頸全歸因於探索噪音。17200有探索在本次樣本明顯提早結束，提示探索脆弱性，單seed不能估計失敗機率或認定策略整體退化。17200無探索步數稍長但距離統計較差，不能以reward略升稱全面改善；不同持續時間的整體RMS亦非相同時間區段配對。

終端obs7還原guidance距離均約50m，獨立有限原路線距離也超過50m。終端obs3還原roll約5–6度，符合距離而非roll閾值的證據；這不是控制／導引物理根因證明。action_saturation_fraction=0也不證明控制能力充分。

保持原PPO paused，先取得兩個已生成report資料夾中的四份diagnostics traces與scenarios，分析偏離開始的位置、guidance／window／控制訊號；不重跑同樣四次、不直接降LR、不啟動17200長attempt配方。SAC仍為獨立候選，不能冒稱已修好本次問題。find_system警告是未來版本搜尋行為提示，四次評估均正常完成。

## 收到軌跡後的初步核對

根目錄 `round3-paired-review-20261020-201402.zip` 已在本機解壓並以 MATLAB 唯讀分析。本機計算 SHA256：`af5437f77a33c651330b626e54dc00ddaf5188620eb94821e2ad5bc7422ad0ef`，未取得遠端獨立雜湊核對。衍生圖表、訊號CSV與summary位於 `artifacts/incoming/round3-analysis/`；不是新sim或新訓練。

- 16000無探索與有探索分別於165.8／164.9秒，在左下轉彎附近終止，終點(E,N)約(-1038.39,-442.53)／(-1030.41,-460.48)m。
- 17200無探索走過左下轉彎，178.6秒於左側向北路段終止，終點約(-949.74,-162.35)m。
- 17200有探索53秒就在右側向南路段終止，終點約(449.65,-342.30)m。

因此四次並非全在同一個彎點失敗。尚未完成window更新／控制因果驗證，不能由終點判定導引實作錯誤或LR根因。

使用者詢問SAC何時執行：建議下一輪改為獨立SAC初試，不必將完整PPO根因分析列為開跑前置。保留原PPO paused，同spatial_v2與八階段門檻，從新agent開始，首次maxAttempts=1、episodesPerProcess=1000、checkpointEvery=100；由使用者在遠端準備與啟動。GPU／6workers與長期收斂尚未驗證，初試不是改善保證。
