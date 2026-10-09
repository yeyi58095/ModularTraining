# PPO LSTM128：穩定性調參 v1（2026-09-23）

模型名稱：`ppo_lstm128_tuned_stability_20260923_v1`。
狀態：已建立的調參假設，尚未完成新模型訓練或成效比較。

驗證：`tests/test_tuned_profile.m` 已在 MATLAB R2024b 通過。確認僅修改預定的兩項 PPO 參數、agent 可建立且輸出有效 action、拒絕原版參數錯配、設定可保存，並能從原始碼快照建立相同設定的 agent。測試產生的空白實驗已清除。

## 數據依據

來源為旁邊 `Simulink/training_autoretry_sessions/20260922_122929_tp02dc5edf_2a72_40db_9688_ae5cdbc2383e/attempt_*/stdout.log`，截至 episode 29000。
以現有 `plot_training_rewards.py` 的解析器重讀原始日誌，而非僅依據預覽 CSV；29 個有回合資料的 attempts、29000 個連續回合，沒有重複回合行。
相同 session 的訓練腳本快照所列 PPO/LSTM128 參數與原始 `ppo_lstm128` 相符。

| 指標 | 觀察值 |
| --- | ---: |
| 最佳 50 回合 reward 平均 | 2218.01（截至回合 9477） |
| 最後 50 回合 reward 平均 | 119.85 |
| 回合 10001–15000 平均 reward / 平均步數 | 1751.72 / 2099.52 |
| 最後 1000 回合平均 reward / 平均步數 | 506.50 / 637.29 |
| 最後 500 回合平均 reward / 平均步數 | 161.69 / 222.65 |
| 最後 500 回合少於 256 步比例 | 73.2% |
| 最後 500 回合達到 3000 步比例 | 0% |

中途曾有較長的存活時間與較高回報，後期卻明顯退步，因此這次優先測試較保守的策略更新。這些統計不是 learning rate 過大的因果證明：路徑、風場、隨機性和 worker 降級都可能影響結果。
完成的紀錄中有 10 次 pool_start_failed、4 次 startup_timeout；17000 回合使用 6 workers，12000 回合使用 4 workers。PPO 調參不能解決啟動或授權問題。
未分析到 KL、策略 entropy、梯度範數或 critic loss 的時間序列，不能由 reward 單獨判定 critic 失效、探索過多或最適參數。

## 本次變更

| 參數 | 原版 | 本版 | 調整假設 |
| --- | ---: | ---: | --- |
| actorLearnRate | 5e-5 | 2.5e-5 | 降低 actor 每次梯度更新的步長 |
| numEpoch | 3 | 2 | 減少對同批經驗的重複優化輪數 |

兩個數值是基於退步現象選出的保守試驗值，不是由資料估計出的最適值；同時變更兩項也無法單獨歸因其效果。代價可能是前期學習較慢。
criticLearnRate=1e-4、entropyLossWeight=0.01、discountFactor=0.98、miniBatchSize=128、experienceHorizon=512、LSTM128 和 reward／成功門檻均維持原值。
尤其 MiniBatchSize 對 recurrent PPO 也代表訓練軌跡長度；此輪先保留 128，不因後期失敗就同時增加序列長度、記憶體需求與其他變因。

參數語意參考 [MathWorks rlPPOAgentOptions](https://www.mathworks.com/help/reinforcement-learning/ref/rl.option.rlppoagentoptions.html)。實作相容性以本機 R2024b 的建立與選項驗證為準；不套用新版新增選項。

## 使用

MATLAB 切換到 ModularTraining 後：

```matlab
info = retry(model="ppo_lstm128_tuned_stability_20260923_v1", workers=6);
```

新訓練會從頭建立 agent，成果存於本資料夾的 `runs/<時間_唯一碼>/`。原版模型與原版實驗保持原有設定；不能用原版 checkpoint 當作這個新 profile 的續訓，因為 PPO 選項不同。
只檢查設定可加 `start=false`。本次開發驗證沒有啟動正式訓練。

## 如何判斷是否改善

先比較相同總環境步數下的最近 1000 回合平均 reward、少於 256 步比例、達 3000 步比例，並一起記錄 wall time 和實際 worker 數。完整結果也應看整段曲線，不能只看最高 reward。
基準資料累計約 3928 萬步；較慢的保守更新不宜只在初期少量回合就判定失敗。
第一輪作探索性比較；確認效果需原版與本版在相同環境、相同固定 worker 數及多組配對 seed 下重跑，並用獨立且相同的測試路徑與風場評估。現有入口的 seed 由 attempt 編號決定，單次對比不足以宣稱改善。
若要歸因，後續再分別測試僅減半 actorLearnRate、僅減少 numEpoch。

## 重建統計

從專案根目錄執行 `python +trainingmodels/ppo_lstm128_tuned_stability_20260923_v1/analyze_training.py "原始實驗資料夾" --diagnostics "對應診斷資料夾"`。來源須有完整連續回合與 worker CSV；不再假設相鄰 Simulink。
預設把完整 `evidence.json` 寫在指定實驗內，可用 `--output` 改位置；不自動覆蓋本資料夾保留的歷史證據。JSON 保存區間與 worker 統計及每個 stdout.log SHA-256，也保留來源路徑；適合本機追溯。若要透過 GitHub 分享，使用根目錄 `export_training_report.py`。
