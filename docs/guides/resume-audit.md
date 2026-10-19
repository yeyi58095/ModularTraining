# 續訓退步唯讀稽核

訓練維持 paused/stopped，在專案根目錄執行：

```matlab
audit = trainingtools.audit_training_resume(info.sessionDir,episodes=[10600 10700 11000]);
disp(jsonencode(audit,PrettyPrint=true))
```

工具取得 supervisor 排他鎖，不 train、不 sim、不更動 checkpoint 或 guard。輸出在該 run 的 reports/resume_audit_*.json，沿用 Git 忽略規則。

- checkpoints 比較所選 checkpoint 與第一個 checkpoint 的 actor／critic 可學習參數，並列出 PPO 主要設定。relative_l2_change 是差異大小，不是故障判定門檻。
- initial_snapshots 讀取 runs/r*/Agent_Initial.mat 和同層 TrainingOptions.mat，依實際 resume checkpoint 歷史對照。這個快照在 train 呼叫之前保存。exact_equal=true 支持載入時保留可學習參數；不保證後續訓練或 optimizer 內部狀態正確。
- options_equal 僅比較工具列出的設定，未涵蓋全部 agent 屬性。Worker seeds 和實際 workers 一併列出。
- 只使用同一 run 下 checkpoints 內的來源檔，避免遷移後舊絕對路徑。無法對應來源或缺少 TrainingOptions 的初始快照會跳過。initial_snapshot_count=0 不能解讀成載入一致。

工具不讀取 optimizer 私有狀態，不分析物理終止原因；不會因看到權重差異就自動降低學習率或回滾。實驗室 MAT 不在本機，需使用者貼回 JSON 才能判斷實際續訓載入是否一致。

本機驗證：使用既有真實短測 agent，加上合成的初始快照與舊電腦路徑配置，確認同 run 解析、相同 actor／critic 參數、設定比對及來源 checkpoint 雜湊不變。未啟動訓練或模擬；不能當作實驗室稽核結果。
