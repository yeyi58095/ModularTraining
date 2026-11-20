# SAC 分支回顧與下一輪的判斷依據

這次盤點 I: 可查到的三個 SAC 課程，共 24 個正式實驗路徑，其中 22 個有訓練 attempt，其餘兩個僅準備。另查對相關凍結評估、失敗軌跡診斷、replay 稽核和過往有界測試。各分支照保存回合與父 checkpoint 核對，訓練曲線沿 `parent_episode` 裁切，不把父 run 之後的嘗試接進來。全部為既有資料，MATLAB 只載入已存的 `TrainingResults.mat` 讀取計數，沒有呼叫 train 或 sim。

## 1600 的 reward 與 1700 的用途

本表是目前 1750 的同一條 lineage，1600 為弱風階段的 SHA `45e57ddc…`，1700 為第二輪 500k final `a08df500…`，1750 為 final `750ce31d…`。同回合編號的其他模型各自保留。

| 保存回合 | 當回合 reward | 末 50 平均 reward | 末 100 平均 reward | 末 50 跑滿 |
| --- | ---: | ---: | ---: | ---: |
| 1600 | 2448.35 | 2083.35 | 1960.13 | 38/50 |
| 1700 | 2393.90 | 2344.76 | 2281.44 | 46/50 |
| 1750 | 2413.13 | 2307.67 | 2326.22 | 43/50 |

1600 的當回合 reward 確實比後兩者高，1700 的末 50 平均最高，1750 的末 100 平均最高。1750 的末百包含 1700 之前的 50 回合。這些是探索訓練中的歷史統計，各段路線與訓練 seed 有差。

1700 曾作為接續來源，是因為和 1600 在兩批合計 40 條不同路線、每條兩風況的凍結配對中，跑滿由 70/80 增至 80/80，reward 均值由 2384.63 到 2508.21。再限雙方都跑滿的 70 組，reward 平均由 2438.91 到 2509.16，前 10 秒後的獨立路線 RMS 平均由 8.98 m 到 8.40 m，逐趟最大偏差的平均由 26.90 m 到 25.08 m。若要求跑滿、RMS ≤10 m 且最大偏差 ≤20 m，全部情境只由 11/80 到 15/80。這支持拿 1700 當較穩定的**對照**，尚未選定下一輪起跑 checkpoint。1750 目前只有一條新路線的 1700 配對，D: 原定 80 趟未取得完整結果。[500k 複驗](sac-replay-replication-result-2026-11-19.md) · [新路線凍結](sac-replay-holdout-result-2026-11-19.md) · [1750 小樣本](sac-replay-1750-capacity-2026-11-20.md)

## 三個課程的分支

### 固定路線 LSTM

| Run | 起點 → 已保存回合 | 階段 | Replay 容量 |
| --- | --- | ---: | ---: |
| [LSTM 從頭，GPU 6 workers](../../experiments/sac_spatial_v2/runs/20261020_201931_tpad1142e4_44c3_4019_a786_72e4faa3b614/model.json) | 從頭 → 3000 | 1 | 100k |
| [LSTM 從頭，serial CPU](../../experiments/sac_spatial_v2/runs/20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b/model.json) | 從頭 → 2000 | 1 | 100k |
| [LSTM replay 初次準備](../../experiments/sac_spatial_v2/runs/20261022_132700_recovery_tp4c73786a/model.json) | 僅準備，無 attempt | 1 | 100k |
| [LSTM 100k replay](../../experiments/sac_spatial_v2/runs/20261023_203402_recovery_tp85477afc/model.json) | 1100 → 1600 | 1 | 100k |
| [LSTM 500k replay](../../experiments/sac_spatial_v2/runs/20261023_204044_recovery_tp6038f3af/model.json) | 1100 → 1600 | 1 | 500k |
| [LSTM actor 原速](../../experiments/sac_spatial_v2/runs/20261025_235136_recovery_tpb9f03642/model.json) | 1600 → 2100 | 1 | 100k |
| [LSTM actor 5e-5 → 1e-5](../../experiments/sac_spatial_v2/runs/20261025_235817_recovery_tpd681ba86/model.json) | 1600 → 2100 | 1 | 100k |

固定無風、Stage 1。平行從頭至 3000 缺同等凍結結果。Serial CPU 的 1100／1300 凍結可跑滿，後段最大偏差 2.63→26.08 m，1500 和 2000 關探索約 95／142 步。500k 對 100k 在 1400 從 85→3000 步，在 1600 卻從 3000→208 步，且 500k 多 40.3% 互動步數。Actor 降到 1e-5 後的 2100 在窄情境跑滿，但後段最大偏差 6.65 m，父組 1600 約 0.98 m。早期資料支持退步可在同一階段與同一 attempt 中發生。容量、保存 replay 和增加互動量在這些試驗難以拆開。[早期證據索引](sac-evidence-full-review-2026-10-27.md) · [LSTM replay 配對](sac-frozen-pair-2026-10-25.md) · [LSTM LR 配對](sac-actor-final-evaluation-2026-10-26.md)

### 固定路線 MLP

| Run | 起點 → 已保存回合 | 階段 | Replay 容量 |
| --- | --- | ---: | ---: |
| [MLP 從頭](../../experiments/sac_mlp_stage1_v1/runs/20261026_184028_tpcff39fc6_3ef5_4435_bfaa_cfffd7ebc83f/model.json) | 從頭 → 1000 | 1 | 100k |
| [MLP 原參數接續](../../experiments/sac_mlp_stage1_v1/runs/20261026_203618_recovery_tp18ecff57/model.json) | 1000 → 2500 | 1 | 100k |
| [MLP 低 actor 準備中斷](../../experiments/sac_mlp_stage1_v1/runs/20261027_005349_recovery_tp5b1807e3.preparing/model.json) | 僅準備，無 attempt | 1 | 100k |
| [MLP actor 5e-5 → 1e-5](../../experiments/sac_mlp_stage1_v1/runs/20261027_015231_recovery_tpbbe84468/model.json) | 2100 → 2500 | 1 | 100k |
| [MLP critic 1e-4 → 2e-5](../../experiments/sac_mlp_stage1_v1/runs/20261027_095822_recovery_tpbc5e6c87/model.json) | 2100 → 2500 | 1 | 100k |

移除 LSTM 仍有跑滿、崩落、再恢復的情況。原配方凍結 2100／2300／2500 為 3000／120／3000 步，兩個跑滿點後段最大偏差 3.49／17.95 m。低 actor 子組先連續跑滿 82 回合，2500 凍結只 133 步。較低 critic 子組先跑滿 119 回合，2200 凍結可跑滿，2500 剩 163 步。低 critic 分支沿用已降低的 actor，且新互動量比低 actor 組多 42.9%。固定無風案例的短期恢復不宜套到隨機路線 Stage 2。[MLP 原版](sac-mlp-frozen-next-2026-10-27.md) · [低 actor](sac-mlp-slow-frozen-2026-10-27.md) · [低 critic](sac-mlp-critic-frozen-2026-10-28.md)

### 隨機路線 Paper64

| Run | 起點 → 已保存回合 | 階段 | Replay 容量 |
| --- | --- | ---: | ---: |
| [Paper64 從頭無風](../../experiments/sac_random_route_v1/runs/20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580/model.json) | 從頭 → 1600 | 1 | 50k |
| [提早加入弱風](../../experiments/sac_random_route_v1/runs/20261105_210649_recovery_tpb199bcee/model.json) | 1000 → 1500 | 2 | 50k |
| [Paper64 actor 初次減半](../../experiments/sac_random_route_v1/runs/20261107_002801_recovery_tpbb65eb4c/model.json) | 1100 → 1500 | 2 | 50k |
| [半速原配方延長](../../experiments/sac_random_route_v1/runs/20261107_132924_recovery_tp578fea3e/model.json) | 1500 → 2000 | 2 | 50k |
| [選定 1600 後原配方延長](../../experiments/sac_random_route_v1/runs/20261114_211021_recovery_tp4c32126b/model.json) | 1600 → 2100 | 2 | 50k |
| [Actor 試驗原速](../../experiments/sac_random_route_v1/runs/20261116_174713_recovery_tp4d3827cd/model.json) | 1600 → 1700 | 2 | 50k |
| [Actor 再減半](../../experiments/sac_random_route_v1/runs/20261117_001300_recovery_tp0c3b83f1/model.json) | 1600 → 1700 | 2 | 50k |
| [Replay 對照一 50k](../../experiments/sac_random_route_v1/runs/20261118_061410_recovery_tp41069d40/model.json) | 1600 → 1700 | 2 | 50k |
| [Replay 對照一 500k](../../experiments/sac_random_route_v1/runs/20261118_095452_recovery_tp078c2c16/model.json) | 1600 → 1700 | 2 | 500k |
| [Replay 對照二 50k](../../experiments/sac_random_route_v1/runs/20261118_212143_recovery_tp99cd10f3/model.json) | 1600 → 1700 | 2 | 50k |
| [Replay 對照二 500k](../../experiments/sac_random_route_v1/runs/20261119_004245_recovery_tpf24d3776/model.json) | 1600 → 1700 | 2 | 500k |
| [500k 再接續 50 回合](../../experiments/sac_random_route_v1/runs/20261119_215607_recovery_tp8e31a177/model.json) | 1700 → 1750 | 2 | 500k |

原本無風至 1600 仍在 Stage 1。從 1000 提早引入弱風是另建試驗，無自然升階。弱風分支的 1100 曾在兩風況各 10/10，1300→1400 訓練 reward 約 1761→1898、凍結跑滿卻 18/20→3/20。到 1500，同五條路線在無風與弱風都失敗。初次 actor 減半，弱風的實際有風小樣本 4/8→6/8，無風 5/10→3/10。有好轉也有代價。半速延長挑出的 1600 曾在兩風況各 10/10，原配方續到 2100 剩 1/20。Actor 再減半試驗從同一 1600 出發，原速／半速最後 11/40／7/40，起點 38/40。另行打開探索，挑出的失敗案例沒有救回。共同起始觀測的第一個動作由 −0.983 變為 +0.058／+0.977，兩臂多數配對的相鄰動作變化反而降低，尚未確立物理或學習根因。[弱風回溯](sac-wind-history-2026-11-06.md) · [子組回溯](sac-child-history-result-2026-11-16.md) · [Actor 對照](sac-actor-pilot-result-2026-11-17.md) · [失敗軌跡](sac-pilot-failure-traces-2026-11-17.md) · [探索對照](sac-pilot-exploration-result-2026-11-18.md)

50k 對 500k 的凍結跑滿是 13/40→32/40 及 8/40→40/40，方向跨兩個訓練 seed 重現。500k 兩輪都經實際核對完整保留來源的 50,000 筆。第一輪篩選未全過，第二輪通過。容量與學習率不變的 1750 分支完整保留父 replay，但一條新路線上 reward 增加、後段 RMS 與最大偏差也增大。750k 驗證了容量及同情境前 300 步的策略一致性，尚無 750k 學習後的結果。[Replay 第一輪](sac-replay-retention-result-2026-11-18.md) · [Replay 複驗](sac-replay-replication-result-2026-11-19.md) · [1750 容量](sac-replay-1750-capacity-2026-11-20.md)

## 三個比再調一次 LR 更有鑑別力的角度

1. **看偏差如何分布。** 1700→1750 新路線中，後段在 10 m 內的比例在無風從 73.3% 升至 79.3%，弱風從 72.2% 升至 79.6%，但兩風況的 p95 與最大偏差都升高。這條路線的多數時間改善和尾端惡化可以同時發生。1600→1700 兩者都飛滿的 70 個情境中，也有 23 組 reward 增加、最大偏差變大。以無風 seed 2000011502 為例，reward +45.65，最大偏差 19.90→36.21 m。這些已保存的情境可先用來定位問題。先用同一批預先選定的直線、急彎和連續轉彎路線凍結比 1600／1700／1750。把跑滿、等時長後段 RMS、p95、最大偏差和超過 20 m 時間分開。若只挑 reward 上升但偏差變大的情境，先拆 reward 各項，再檢查轉彎段的動作、roll 與偏離時間。既有 spatial_v2 reward 含多項局部訊號，獨立有限路線最大偏差用來補足這個角度。正式課程門檻仍照原快照。[Reward 結構](../guides/spatial-v2.md)
2. **把互動步數和實際更新一起量。** 新從 I: 的 R2024b 保存結果讀出四個單 attempt 的累計 actor 梯度計數。首筆為零、分支內單調，所以用末值，不加總逐回合欄位。第一輪 50k／500k 各 244,656／276,866（+13.17%），環境步數 252,117／288,866。第二輪各 229,292／275,132（+19.99%），環境步數 238,517／287,132。這些數是保存的梯度計數，不能當作同一筆 replay 被抽過幾次。若將來要隔離保留效果，兩臂從同一 checkpoint 開始，預先對齊新增環境步數與更新預算，分開記保留量、抽樣資料和尾部偏差。也可以在同一容量下比較不同來源經驗保留策略，當成另一個試驗。
3. **用固定策略判斷是否值得再更新。** 退步在固定無風及弱風都出現，1500／1600 的好點也可能在短期續訓後消失。不能從共同觀測上動作改變或 entropy 的增減，直接判定再調某個 LR 會改善。比較 checkpoint 時同時保留 1600 對照和 500k 1700 候選。先判斷同情境下哪些失敗有可重現的型態，再決定要測資料保留、更新強度或 reward 取捨。若回到移動目標任務，循跡只有中間指標，還需另定目標可觀測與失追指標，現有數據未量到那些結果。

可重算資料在 I: `artifacts/incoming/sac-branch-review-20261120/`，包含 `branch-catalogue.csv`、`comparison-summary.json`、`saved-gradient-counts.json` 及兩份分析腳本。這次僅紀錄，訓練與續訓由使用者親自執行。
