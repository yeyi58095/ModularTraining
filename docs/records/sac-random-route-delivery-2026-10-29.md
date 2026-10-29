# Random-route SAC delivery and verification

使用者授權：從第一回合隨機路線、分階段增加風、參考Dally論文的新SAC配方；完成實作、必要測試、日誌、Git push及遠端執行／監看／繪圖指令。meeting暫停數週，不碰簡報。遠端未連線、未啟訓練。

## 最終設計

- experiments/sac_random_route_v1，sac_paper64兩層64＋LayerNorm／ReLU＋獨立雙Q；原10維觀測／單一橫向命令與spatial_v2保持。
- paper-inspired：buffer50k／batch256／gamma.99／LR固定3e-4／frequency1。採論文高度固定LR而非姿態線性降零；不宣稱原文復現。Gaussian std使用softplus，取樣時間仍0.1秒。
- 4階段：無風、分量±1、±2＋turbulence0..1、±3＋turbulence0..2；水平風最大約4.24m/s。路線幾何保持一致，每worker每回合換seed，當回合不變。
- 既有random生成器限制：15m/s、70m高度、直線約225–750m、目標轉角40–80度、名義半徑約153m、約6km；起點與起始方向固定，未排除自交，也未證明物理可追蹤。沒有「完全不受限」路線。
- 訓練seed初值28001，各attempt偏移10000；route seeds1..1e9，驗證seed2000000101..105。route_seeds.csv與wind_all.csv紀錄worker-local回合，非全域episode映射；parallel時序與內部湍流不能僅靠seed完全重現。
- 每stage至少1000／最多5000回合，總20k（60m步理論上限）。首段500、checkpoint100、maxAttempts1、guard退步pause／預算啟用。保持episode checkpoint節奏；沒有實作精確等互動步數中斷，本配方不是等步數因果對照。
- 訓練3個100回合窗均需reward2200、steps2800、滿3000步率90%；達標後先保存paused。當前stage＋無風固定5路線皆跑滿，後10秒原路線max<=20m／RMS<=10m才放行。這是新驗收標準，不修改50m isDone。驗證集用於升階，不當獨立最終test set。
- frozen_gate按checkpoint SHA、課程／環境／runtime／generator SHA、關探索、baseline、完整route metrics與每條seed核對，缺漏／過期／失敗報告均不放行。評估只由使用者啟動；review入口精確選Agent_Final，不用同episode數但不同MAT冒充。
- 跨stage同agent／optimizer／replay，不清buffer；checkpoint採v7避免已知HDF5保存路徑問題，但不宣稱根治當機。
- GPU＋同步6 process workers，minWorkers6且無靜默降數量；建構與硬體能力檢查不等於六workers性能證明。

## 驗證證據

- 修改執行程式前Get-Process MATLAB無程序；CIM在沙盒不可用，未以CIM失敗當無程序證據。
- 10/28 paper網路及課程建構通過。test_sac_random：64有界合成CPU學習、actor改變、v7保存續載、optimizer／PolicyState與replay保留；路線同seed跨風一致、異seed不同；missing／failed gate拒絕。
- test_sac_mlp：舊MLP／recurrent建構回歸及64步合成保存接續通過。
- 10/29 test_curriculum：schema、all/any、連續窗口、MAT快照、stage接續、完成／預算pause、假引擎接線通過。
- preflight_sac_random('gpu',6)：本機R2024b、RTX4070 Laptop GPU、profile容許6workers、GPU網路建構通過。未在此檢查配置6-worker pool。
- test_sac_random_flight：fixture `experiments/curriculum/runs/20261029_060236_tp7ab015eb_4da9_4d32_a037_900c052a9ee4`，parallel CPU／1worker／兩個合成stage門檻，實際80及96步，正常保存並跨程序沿用actor權重與replay；v7及FastRestart off驗證，5步關探索評估weights_unchanged。不是正式課程通關。
- 本機圖表回歸：test_curriculum_progress 2項、test_plot_stages 6項通過；先因缺matplotlib／沙盒TEMP失敗，補測試依賴於tests/output/plot-deps並用workspace TEMP後通過，未改系統Python。
- 正式遠端6workers＋GPU吞吐、長期學習、泛化、四階段完成尚未驗證。完整原始測試輸出留tests/output（Git忽略）。
- 最終補測test_sac_random通過：缺seed、錯checkpoint SHA、探索報告及只有無風卻要升後期stage皆拒絕；精確Agent_Final選取／routeMetrics5步評估通過，來源SHA一致。此短評估不能通過3000步升階門檻。

## 操作入口

[完整指南](../guides/sac-random-route-2026-10-29.md)：pull、preflight、prepare、單次啟動、training_status、每6秒圖、凍結評估、同run接續與正常段末暫停。新收據 `artifacts/sac-random-route-v1-run.txt`。

上次工具中斷為自動核准審查用量耗盡；未執行的修正已於10/29重新核對再套用。沒有將「已提出的patch」當成已寫入。
