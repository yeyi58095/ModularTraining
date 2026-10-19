# Progressive v2：在空間循跡環境從頭訓練

> 2026-10-15 校準註記：下表 reward 門檻仍為未校準草案，不能作為 reward v2 的正式升級門檻。新候選目前只供離線重計分，未部署 SLX；遠端設定保持 start=false。公式、證據與限制見 [reward 校準](../research/reward-calibration-v2.md)。

2026-10-15 使用者明確指定本課程改用 schema 2、`environment: spatial_v2`。新 run 使用新版 reward 並保存環境快照；既有 spatial_v1 run 不改寫。

使用獨立的 [spatial_v2 SLX](spatial-v2.md)，不更改共用 runtime SLX。下列課程數值維持原規劃，尚未經新 reward 從頭訓練校準，不代表保證過關或合格。

2026-10-14 使用者確認另建 progressive_v2，供新 agent 從第一階段開始訓練。設定在 `experiments/progressive_v2/curriculum.json`，不接續 recovery checkpoint；階段之間則始終沿用同一 agent。這是可由現有 schema 執行的起始方案，尚未進行從頭訓練或校準門檻。

## 環境與模型

從第一回合使用目前正式空間循跡環境：首次有效 window、末端 lookahead v2、有效歷史路徑、依飛機局部單調進度更新路段。無風與有風都適用；任務是沿指定路徑飛行，不是追蹤按原時序移動的目標。reward 改用 spatial_reward_v2，終止門檻不變。

`spatial_v1` 的模型 SHA256 為 `495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be`。環境 manifest 與 run 副本會核對此 SHA；共用引擎和工具箱版本仍須另記錄。現有 31600 的評估不能替代新 agent 的從頭收斂驗證。

模型仍為 `ppo_lstm128`。目前 profile 的 actor LR 是 5e-5、critic LR 是 1e-4；新 agent 不會自動繼承 recovery 的 actor LR 2.5e-5。先保留基準 profile，因先前退步涉及環境問題，尚無證據證明從零訓練必須減半 LR。本次不更動 PPO、網路或 runtime。

## 八階段設定

所有 reward、平均步數、跑滿比例條件，都要求最近三個不重疊的 100 回合區間各自達標，並同時滿足最低回合數。跑滿定義為步數 ≥3000，不是獨立的任務成功旗標。

| 階段 | 路徑 | 東／北風各自範圍 m/s | turbulence 等級 | 最低回合 | reward 平均 | 步數平均 | 跑滿比例 | 回合上限 |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 直線 MAT | 0 | 0 | 2000 | 1200 | 2700 | 80% | 25000 |
| 2 | 平緩 S 彎 MAT | 0 | 0 | 3000 | 1800 | 2750 | 85% | 20000 |
| 3 | 內建固定轉彎 | 0 | 0 | 3000 | 2000 | 2800 | 90% | 20000 |
| 4 | 隨機路徑 | 0 | 0 | 5000 | 2200 | 2800 | 90% | 30000 |
| 5 | 隨機路徑 | −1～1 | 0 | 2000 | 2200 | 2800 | 90% | 15000 |
| 6 | 隨機路徑 | −1～1 | 0～1 | 3000 | 2200 | 2800 | 90% | 20000 |
| 7 | 隨機路徑 | −3～3 | 0～1 | 5000 | 2200 | 2800 | 90% | 25000 |
| 8 | 隨機路徑 | −3～3 | 0～2 | 10000 | 2200 | 2900 | 95% | 40000 |

最低回合合計 33000，預算合計 195000；不是耗時預測，也不要求跑滿上限。每階段未達標用盡預算都 pause。若同時達標及到上限，現有引擎優先判定通過。

風速及 turbulence 是現有實作的整數抽樣範圍，turbulence 等級不是 m/s。每回合抽樣，因此強風階段也含無風／低風樣本。隨機路徑保留每 worker 本地每 10 回合更新，避免同時更動課程與抽樣頻率；重啟會重設本地計數。

## 與 v1 的差異及理由

- 保留前三種固定幾何與第四階段無風隨機路徑，先建立能力再處理路徑變化。直線與 S 彎使用與 v1 相同的可重建幾何，但資產獨立放在 v2。
- 風擾從兩階段拆成四階段：先加入小風，再增加 turbulence，再擴大平均風範圍，最後提高 turbulence 上限。每次只更動一類風場設定，並不保證任務難度線性增加。
- 所有階段加入跑滿比例，並提高前段平均步數門檻，避免少數長回合拉高平均後過早升級。仍保留逐漸提高的前段最低回合數，尚不根據舊分支歷史縮短基礎訓練。
- 隨機階段 reward 下限統一暫定 2200，不再隨風加大而要求更高 reward。v1 的 2400／2700 尚未在一致的新環境校準；2200 同樣只是暫定品質下限，不能視為經驗證的循跡誤差標準。
- 最終跑滿比例由 v1 的 80% 提高到 95%，配合平均步數 2900。但仍可能有 5% 提前終止，且未對最強風子群單獨判定，不能稱為整體合格。

## 準備與預檢（不訓練）

在專案根目錄的 MATLAB 執行：

```matlab
inputs = trainingtools.prepare_progressive_v2_training();
% 只生成 v2/assets 的直線及 S 彎，並呼叫 curriculum_plan 驗證。
```

函式不建立 run、agent 或 pool。既有 MAT 內容不同時拒絕覆寫。MAT 不納入 Git，兩台電腦各自生成。舊的 `trainingtools.prepare_progressive_training()` 與 `configs/lab_gpu6.json` 仍指向 v1，不會自動切到 v2。

若僅閱讀尚未生成 MAT 的計畫，可執行：

```matlab
plan = curriculum_plan("experiments/progressive_v2/curriculum.json",checkFiles=false);
```

未來另行準備正式 run 時，應明確指定這份課程、3000 步 episode 上限、checkpointEvery=100、episodesPerProcess=100，以及當時確認的硬體設定。100 回合一段讓條件在較近的保存邊界評估，也有重啟／建池成本。硬體和分段參數不是 curriculum schema 欄位。本次僅規劃及無訓練預檢，不建立正式 run、不啟動訓練。

## 獨立評估與合格判定

JSON 的門檻只看 checkpoint 保存的訓練歷史，通過後會由現有引擎自動換階段；沒有人工審核 gate，也不會自動啟動獨立評估。不可把下面的規劃當作已接入引擎的功能。

未來至少在無風隨機、小風含擾動、完整風三個里程碑保存並評估 checkpoint。以預先固定、不同於訓練抽樣的情境測試，對前期固定任務做能力保留檢查，並分開列出無風、小風、強風及各 turbulence 等級的結果；不以含大量低風樣本的整體平均掩蓋強風失敗。比較 checkpoint 時使用相同情境配對。

除了跑滿比例和 reward，需查看獨立原始路線距離的 RMS、尾端偏差及終止原因證據。初始 t=0 偏差與後續飛行需分開報告，不能把初始瞬間最大值直接當穩態表現。距離品質門檻目前尚無經確認的需求，不能在 JSON 虛構不支援的 CTE metric。需要人工評估後才允許升級的話，須另做引擎功能，不在這次規劃範圍。

本課程也不自動建立 recovery 專用 training_guard、不回滾、不選最佳模型。既有 recovery 的停訓機制不能假設會由這份 JSON 自動繼承。新環境下若低分，先核對 traces、版本及獨立評估，再決定是否調整下一版門檻或學習參數；已建立 run 的快照不直接改寫。

## 遠端執行安排

使用者確認正式訓練主要在遠端電腦，本機可先測試。`configs/lab_gpu6_progressive_v2.json` 沿用先前遠端 GPU、最多 6 workers／最低 1 worker 的設定，改用 v2、100 回合一段，並明確設置 `start:false`。這是遠端預檢配方，尚未驗證遠端 GPU 或多 worker 執行。

確認遠端副本沒有活動訓練，依環境更新指南先保存舊 run 的當地環境，再同步包含這次新增檔案的提交。遠端在專案根目錄執行：

```matlab
inputs = trainingtools.prepare_progressive_v2_training();
cfg = jsondecode(fileread("configs/lab_gpu6_progressive_v2.json"));
args = namedargs2cell(cfg);
info = retry(args{:}); % start=false，只建立新 run 設定快照
disp(info.sessionDir)
```

每次重跑 retry 都建立另一個新 run，請保存 sessionDir。正式開始時另行確認環境版本及快照，再對該 sessionDir 執行 resume；目前不需啟動。MAT 由遠端自行生成，無需複製本機絕對路徑。這裡的步驟不包含純腳本重寫，沿用目前 MATLAB／Simulink 引擎。

## 本次驗證

2026-10-14 在本機 MATLAB R2024b 通過八階段 schema 與實際 MAT 載入檢查；連續執行兩次準備函式確認輸入可重用。各階段以合成歷史確認：達標可 advance、最低回合不足維持 continue、三個區間中任一區間跑滿比例不足維持 continue、預算用盡且不達標會 pause。未建立訓練 run、pool 或執行 sim/train，不能視為收斂驗證。

參考：[從頭訓練決定](../records/from-scratch-training-decision-2026-10-14.md)、[空間循跡驗證](../records/stage6-progress-validation-2026-10-13.md)、[課程 schema](curriculum.md)。
