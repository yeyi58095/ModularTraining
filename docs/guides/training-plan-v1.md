# 漸進式 UAV 訓練流程 v1

目標是讓同一個 PPO agent 先學穩定追蹤，再處理轉彎、陌生路徑與風擾。可執行設定是 `experiments/progressive_v1/curriculum.json`；這是一份待實驗校準的起始方案，不保證收斂，也不是論文參數的精確重現。

## 六個階段

全程沿用 `ppo_lstm128` 的網路與超參數，避免同時改架構、學習率與任務，讓結果比較容易解釋。第一輪先確認課程本身的效果，再另開實驗比較穩定版 profile。

| 階段 | 路徑與環境 | 至少回合 | 平均 reward | 其他條件 | 階段上限 |
| --- | --- | ---: | ---: | --- | ---: |
| 1 | MAT 直線、無風 | 2,000 | ≥1,200 | 平均步數 ≥1,500 | 25,000 |
| 2 | MAT 平緩 S 彎、無風 | 3,000 | ≥1,800 | 平均步數 ≥2,100 | 20,000 |
| 3 | 內建固定轉彎、無風 | 3,000 | ≥2,000 | 平均步數 ≥2,300 | 20,000 |
| 4 | 隨機路徑、無風 | 5,000 | ≥2,200 | 平均步數 ≥2,500 | 30,000 |
| 5 | 隨機路徑、東／北風各 −1～1 m/s、擾動 0～1 | 5,000 | ≥2,400 | 平均步數 ≥2,700 | 30,000 |
| 6 | 隨機路徑、東／北風各 −3～3 m/s、擾動 0～2 | 10,000 | ≥2,700 | 跑滿 3,000 步比例 ≥80% | 40,000 |

每項表現條件都要求最近三個各 100 回合、不重疊的區間分別達標，且必須滿足最低回合數。每階段到上限仍不達標便保存、暫停，不強迫升級。總預算最高 165,000 回合，並非一定要跑滿；理論最少 28,000 回合。步數是持續模擬的代理指標，不等於任務成功率。這些數值是初始工程假設，尚未以長訓練校準；尤其不同路徑的 reward 分布可能不同。

第一階段保留較長探索時間，避免把從零開始的低分誤判成退步。第三階段才加入現有固定路徑的較急轉彎，避免把「固定」誤認為「簡單」。隨機路徑每個 worker 本地每 10 回合更新，程序重啟會重置本地計數。

這個分解方向也與 MathWorks 的 [PPO curriculum 範例](https://www.mathworks.com/help/reinforcement-learning/ug/train-ppo-for-lka-using-curriculum-learning.html)一致：逐步增加路徑曲率，並另外做評估。但其車輛任務的 reward 門檻不能直接套到 UAV。本計畫不是花偉傑論文第一階段路徑的還原；論文背景及原本實作的差異見既有審視紀錄。

## 準備與啟動

在 MATLAB 切到專案根目錄：

```matlab
inputs = trainingtools.prepare_progressive_training();
info = retry(curriculum=inputs.planFile, workers=4, minWorkers=1, ...
    device="cpu", checkpointEvery=100, episodesPerProcess=1000, start=false);
% 檢查 info.sessionDir 中的 model.json、control.json、curriculum.json 後，
% 準備正式訓練時才自行執行下一行：
% info = retry(resume=info.sessionDir);
```

準備函式建立 6 km 的直線與平緩 S 彎，15 m/s、0.1 秒取樣、70 m 高度，並驗證 JSON。既有 MAT 若內容不同，會拒絕覆寫。它不啟動訓練。兩台電腦都執行同一函式即可重建輸入；MAT、完整日誌與 checkpoint 不納入 Git。

4 workers 是可調整的起始上限，不是已測出的最佳值。可改為 6，仍以當次可用的 n 個 workers 執行；最低 1。此版本本機短測試使用 CPU／1 worker，多 worker 吞吐與 GPU 須另外驗證。正式訓練前檢查授權、RAM 與磁碟空間；每 100 回合存檔在整份預算中可能產生約 1,650 個定期 checkpoint，另有分段存檔，尚無自動保留／清理政策。

條件在分段存檔邊界評估，`episodesPerProcess=1000` 代表可能達標後仍多跑到該段結束，並非每 100 回合定期 checkpoint 都立刻換階段。可縮小分段長度換取更快切換，但會增加 MATLAB／pool 重啟成本。上限會限制當段剩餘回合，不會無限重試學習。

首次正式實驗建議先觀察第一個 1,000 回合區間的 episode 長度、失敗原因、wall time 和記憶體；低 reward 本身不足以宣告失敗。後續比較需同時看環境步數與時間，不只回合數。不要從三回合短測試推算收斂或可靠的長跑速度。

## 退步與階段交接

已實作：沿用 checkpoint 與模型權重、階段內統計、連續區間門檻、預算用盡暫停，以及匯出報告時的疑似退步診斷。課程切換後不拿上一種任務的高分直接當新任務基準。

尚未實作：持續背景監測、自動因退步停訓／回滾、獨立評估選最佳 checkpoint，以及每階段學習率／探索量排程。不能把本計畫當成已具備這些能力的無人值守系統。現在可定期執行 `tools/export_training_report.py <session> --machine lab` 或 `dorm`，分享小型報告；診斷規則見 `learning-health.md`。

若同一階段先學會、之後長期變差，先保存目前狀態與報告，確認任務、worker 數、重啟與 checkpoint 接續是否改變，再比較退步前後 checkpoint 的相同測試任務。不要僅依 reward 曲線直接降低 learning rate，或不保留證據就覆寫／回滾 agent。到階段預算而暫停時也應先檢查資料；不要手改實驗內的課程快照來繞過門檻。

下一項建議實作是獨立 evaluator：固定一套未參與訓練的路徑、風場及 seeds，先用約 20 個平衡測試回合，比較追蹤誤差、失敗率與回合長度，再決定是否升級／保留最佳模型。評估時不更新權重，且需確認使用評估策略。MathWorks 提供 [rlEvaluator](https://www.mathworks.com/help/reinforcement-learning/ref/rl.evaluation.rlevaulator.html)；整合前仍須核對本機 R2024b API 與並行限制。訓練 reward 過關僅是目前可執行的第一層門檻。

研究比較最好重複獨立 seeds，但目前 seed 由 attempt 推導，尚無可設定的實驗 root seed；重跑相同設定不能直接聲稱是獨立 seed 實驗。需先補上 seed 入口與記錄，再比較多次結果。

## 雙機與修改規則

Git 同步程式、JSON、文件與精簡報告。完整可續訓實驗要另外搬移 checkpoint 與相關快照，並核對 control.json 的本機路徑。任何 runtime 更新前確認該副本沒有活動訓練。已建立的實驗使用自己的課程與輸入快照，修改原始 JSON 不會改掉它；調整門檻應建立新版本與新實驗，現階段尚無正式的跨計畫 checkpoint 匯入功能。
