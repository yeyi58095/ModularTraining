# 流程圖核對與詳細說明

核對日期：2026-09-24。依據目前工作區程式作靜態檢查，未因此重新執行長時間訓練。簡報第 38–42 頁將整體流程拆成可逐頁說明的內容。

## 執行順序

1. `retry.m` 讀取選定的模型 profile；新實驗建立於 `+trainingmodels/<model>/runs/<experiment>/`。保存 `model.json`、`control.json` 與 `model_source/`。續訓沿用既有實驗設定，並檢查模型與快照。
2. PowerShell supervisor 啟動獨立 MATLAB 程序，執行 `runtime/checkpoint_attempt.m`。它選擇有效 checkpoint、準備 overrides，呼叫 `training.m` 取得 agent 建立與驗證回呼，再執行 `runtime/training_engine.m`。
3. 訓練引擎建立新 agent，或恢復存檔中的 agent 與訓練歷史；驗證相容性，建立平行池並訓練。
4. 預設每 100 回合存檔，每個程序最多追加 1,000 回合。正常返回後保存 `Agent_Final` 與對應歷史，再判斷最近 50 回合平均 reward 是否達 2,900。達標才保存成功模型並發布成功狀態；正常結束本身不代表達標。
5. 未達標時，下一個程序從已保存進度繼續。尚未保存的進度可能遺失，亂數、路徑與部分環境狀態重新初始化，並非完整狀態重播。

## worker 重試條件

**2026-10-09 更新：** 下述 6 → 4 → 2 是 pool 整體失敗後的 supervisor 備援。現在優先用 `[minWorkers,workers]` 在同一次建池取得可用數量（預設 1–6），成功後同一 attempt 直接訓練；WorkerRandomSeeds 與保存的 numWorkers 跟隨實際 pool 大小。下限由 retry 的 minWorkers 設定，舊 control.json 預設 1。部分連線但整個 pool 建立失敗仍不能開始訓練。

- 預設目標為 6 個 worker。只有已進入平行池啟動階段、但未取得 pool-ready 證據的失敗才觸發 6 → 4 → 2 降級；更早的載入失敗不等同建池失敗。
- 降級是在下一個 attempt 重建 pool，不是保留前次連上的部分 worker。
- 成功建池後，下一段恢復目標 worker 數。每回合診斷記錄實際 worker 數。
- 預設啟動逾時 600 秒、日誌無活動逾時 1,800 秒。耗盡備援數量後，連續 3 次無進度失敗會暫停。使用者 STOP 仍可中止；只保留已保存進度。

## 本次修正與閱讀限制

- 圖中的診斷位置已改成 `<experiment>/diagnostics/`；checkpoint 為 `<experiment>/checkpoints/`。舊 `sessions/`、根目錄 `training_diagnostics/` 為相容既有實驗的路徑。
- `training.m` 的角色是提供模型回呼；由單次程序呼叫它。選取 checkpoint 與實際載入 agent 是不同步驟。
- 模型快照包含模型程式，排除訓練輸出，不包含整套 runtime。執行中的實驗仍會受 runtime 修改影響。
- 架構圖是控制與資料關係的摘要，箭頭不全是函式呼叫。HTML 圖例中的 Database 表示保存的資料檔案，並未使用資料庫服務。
- Average reward 下滑與回合縮短為觀察結果；尚未確認因果。保守更新 profile 的建立測試不能當作長時間訓練改善的證據。

## 程式對照

入口與模型：`retry.m`、`training.m`、`+trainingmodels/load_profile.m`。

執行與恢復：`runtime/checkpoint_attempt.m`、`runtime/training_engine.m`、`runtime/checkpoint_select_agent.m`、`runtime/checkpoint_save_final.m`、`runtime/checkpoint_mark_success.m`。

監控與 worker：`runtime/checkpoint_supervisor.ps1`、`runtime/checkpoint_watchdog.ps1`、`runtime/checkpoint_open_pool.m`、`runtime/checkpoint_worker_diagnostics.ps1`。
