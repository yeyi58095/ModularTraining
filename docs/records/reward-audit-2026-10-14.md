# 空間循跡 reward 拆解（2026-10-14）

使用者要求確認 reward 是否需要修改。本次只新增隔離評估記錄及離線拆解工具，不修改正式 SLX、runtime、checkpoint、課程、guard 或門檻，不啟停實驗室訓練。工作區原有「未來從頭重跑」文件及 AGENTS 修改保留。

## 方法與資料範圍

本機 MATLAB R2024b / CPU，以已提供的實驗室 Agent31600、Stage6 seeds202/205 做兩次 frozen-policy sim。不是新實驗 Agent36300 的分析，也不是正在訓練的 episode。正式 SLX SHA 為 `495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be`。

`compare_training_checkpoints(...,rewardDiagnostics=true)` 自動開啟 diagnostics，在暫存副本記錄 OBSERVATION/Sum3 的十個實際輸入、總分、正規化 d/curvature 及 bonus indicator。rewardDiagnostics 預設 false，不增加一般評估的記錄量。`audit_training_rewards(evaluation.outputDir)` 讀保存的 traces，輸出同資料夾的 reward_breakdown.json；不重新 sim 或 train。

RL experience 的 transition reward 標在 t，但對應 signal logging 的 t+0.1 秒。工具明確驗證這個偏移及每筆值，拒絕錯位，沒有直接把 3001 個訊號樣本當 3000 個 reward 加總。兩例十項加總的逐步殘差均為 0，總分與無額外 instrumentation 的既有結果一致，兩例均3000步，權重/checkpoint SHA保持不變。

本機資料：`diagnostic_packages/stage6_review/main/reports/evaluation_20261014_090252_tpa0964215`。MAT traces 約數十MB/例，不納入 Git。完整明細在其中 reward_breakdown.json。

## 各項實得分

| 項目 | seed202 | seed205 |
|---|---:|---:|
| 循跡誤差 | 475.49 | 452.08 |
| 距離變化 | 249.97 | 254.38 |
| 朝向 | 431.28 | 431.94 |
| 曲率與距離組合 | 436.87 | 434.51 |
| 滾轉角速度 | 150.00 | 150.00 |
| 偏航角速度 | 150.00 | 150.00 |
| 轉向追蹤 | 536.01 | 538.37 |
| 距離加分支路（含基底） | 450.65 | 450.65 |
| 動作幅度超限 | 0 | 0 |
| 動作變化扣分 | -38.90 | -38.50 |
| 總 reward | **2841.37** | **2823.42** |

## 確認的評分語義問題

### 1. 舊目標距離加分與新任務不一致

實際支路是 `0.1 * (1 + a + b)`，不是整條支路全都來自目標距離：

- 固定基底：每步0.1，共300分。
- `a=0.5` 當 distance_to_window_target 在30至150m：兩例各僅13/3000步、0.433%，共0.65分。新的 signal 是局部最近 waypoint 距離，不是舊定時移動目標的距離。
- `b=0.5` 當傳入的 d<=10：兩例全程成立，共150分。

因此不能把450.65分全稱為「舊目標距離加分」，也不能说完全沒有拿到這條支路的分数。這個 a 條件對空間循跡存在方向錯置：離路徑變遠到30m反而可能多拿0.05/步；本次樣本只在初始接入階段拿到，尚未證明模型實際利用此漏洞。

### 2. 所謂 d<=10 收到的是 d/30

MATLAB Function22 的 d 來自 MATLAB Function1 正規化輸出，故條件等價於原始 guidance d<=300m，不是10m。正常未終止時 d通常小於50m，因此它幾乎是固定加分。

兩例該條件100%成立，但實際 guidance d<=10m 的樣本比例只有77.97%／58.13%。這項目前無法有效區分是否保持在10m內；修正為物理單位後，分數可能下降，不是為了提高分數而改。

### 3. 曲率判斷有另一個尺度疑點

Function13 收到 `k_normalized=k/(1/55)`，卻以 `abs(k_normalized)>=1/55` 判斷是否將 d 懲罰减半。等價原始曲率門檻為1/3025，而非1/55。兩例當前觸發比例37.27%／37.20%；若設計原意為原始曲率1/55，兩例均不觸發。不能僅憑常數推定原設計意圖，應在新 reward 規格中明列單位與門檻後再修。

## 決策

有理由另立 reward v2：取消舊移動目標距離條件，明確定義以公尺衡量的循跡品質，並釐清曲率門檻；保留控制平順度及物理終止保護。這裡沒有實作或部署 v2，不把尚未評估的公式直接套到活動 run。

**不能據此認定這些問題造成最新訓練平均2474.88。** 同一現行 reward 下，未再訓練的31600在本次兩例仍高於2700，證明2700不是此環境不可達的上限。需要目前run保存的33700、36300或後續checkpoint，在相同情境拆分得分比較，才可解釋新分支的變化；目前本機沒有這些checkpoint。

下一版門檻應與明確的完成率、實際循跡距離、控制平順度一起校準，不直接平移總分，不為了過關降低2700。新舊 reward 另記版本；既有正在執行的實驗保留原定義，待停止/預算結束後再決定分支。

## 使用方式（實驗停止後）

```matlab
evaluation=compare_training_checkpoints(info.sessionDir, ...
    episodes=[31600 33700 36300],includeLatest=false, ...
    stages=6,seeds=[202 205],rewardDiagnostics=true);
audit=audit_training_rewards(evaluation.outputDir);
disp(jsonencode(audit.results,PrettyPrint=true))
```

先確認指定 checkpoint 存在；不為評估覆寫或補造checkpoint。這是小樣本診斷，不代表泛化合格。新增測試 `test_reward_breakdown` 已驗證合成資料加總、時間错位拒絕、距離與曲率正規化判讀；真實兩例另外驗證完整數值一致性。
