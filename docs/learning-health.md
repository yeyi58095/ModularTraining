# 純腳本如何應對學習退步

2026-10-09：使用者指出訓練環境只有腳本，沒有 AI 即時修正。可用確定性的規則實作偵測、保留成果與停損，但必須區分訓練 reward 波動、評估退步與程序故障。

## 已實作：診斷訊號

`learning_health.py` 由 `export_training_report.py` 呼叫。每 1000 個連續回合形成一個不重疊區間；若已有平均 >=500 的參考區間，後面連續 5 個完整區間平均低於先前最佳區間的 50%，標記 `suspected_regression`。例如先前最佳區間平均 1800，連續 5000 回合分段平均都小於 900 才觸發。這避免單回合尖峰或少量失敗立即触發停損。

門檻皆可用 CLI 調整；它們只是初始工程規則，不是已驗證的 PPO 收斂判準。輸出會保存門檻、參考區間、最近完成區間、連續低迷次數與未滿區間的資料數。缺回合會打斷連續低迷計數；舊的最佳區間仍可當參考。

這層只標記：每次匯出才計算，沒有背景服務，不會動 MATLAB、超參數或 checkpoint。它不等於已導入自動退步停訓。圖中實驗仍需在實驗室匯出資料，才能驗證訊號是否符合觀察。

## 後續建議的處置順序（尚未實作）

1. **用相同條件評估候選模型。** 定期用固定且獨立於訓練的路徑／風場／seed 集合測試；只評估，不更新權重。不要直接用不同 worker／風場下的單段訓練 reward 判定模型優劣。評估會增加運算成本，頻率應配合每段 1000 回合的設計。
2. **分開保留最新與最佳模型。** latest 用來恢復進度，best-evaluation 用來保留已取得的能力；兩者保存各自模型、歷史與評估條件。即使後面退步，也不覆蓋 best。尚未有固定評估前，若保留 best-training 也應明確標為暫定候選。
3. **持續退步後在段落邊界安全暫停。** 當多輪獨立評估都下降，先完成並保存當段，再記錄 `paused_regression`，而不是中途殺掉 MATLAB。目前 STOP 會強制終止所屬程序，不能直接拿它充當「保存後暫停」。必須新增 supervisor 在段落邊界的決策與持久化狀態。
4. **恢復試驗另開分支實驗。** 可以事先定義候選策略，例如回到最佳模型、僅降低 actor learning rate，設定最多幾次恢復試驗及總訓練預算。保存父 checkpoint 指紋／父 episode 與新參數，避免不斷回滾、覆蓋歷史、重播同一輪失敗。現有 validator 與同目錄防回滾限制會拒絕部分此類操作，需專門設計 fork-from-checkpoint 入口。

不建議偵測到 training reward 一跌就自動改 learning rate：worker 數、隨機風場、路徑或 episode 提前結束都可能造成同樣曲線；不同故障不適合套同一處方。PPO loss、策略 entropy／KL、action 飽和比例與終止原因的紀錄，可幫助選擇恢復策略。

## Worker 數量變更的關係

現在同一段可以用成功建立的 n 個 workers；下一段可重新嘗試目標上限。比較學習成效時仍要一起看 ActualWorkers、總環境步數與訓練時間。現有 seed 由 attempt 決定，跨段或跨機不是完全相同採樣條件。

採用 MATLAB `parpool(cluster,[minWorkers workers])` 的範圍語意，已核對本機 R2024b 的 parpool 說明與 [MathWorks 文件](https://www.mathworks.com/help/parallel-computing/parpool.html)。此語意容許成功 pool 小於上限，不能保證所有授權／worker 連線錯誤都能自動產生小 pool。整個 pool 失敗時仍需 supervisor 的恢復機制。

## 2026-10-10：手動比較工具

compare_training_checkpoints 已提供停止後的固定無風任務比較，不更新權重；見 [操作與限制](checkpoint-comparison.md)。這補上有限範圍的手動評估入口，仍沒有持續監控、獨立泛化測試集、自動 best 選擇、回滾或分支恢復。
