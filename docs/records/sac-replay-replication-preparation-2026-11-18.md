# Replay replication preparation

使用者授權繼續至可執行下一步。第一輪證據見 [結果](sac-replay-retention-result-2026-11-18.md)。選擇同 Agent1600 的第二個 training seed 配對試驗，而非延長尚未通過 screening 的 500k1700。

- 新入口 `trainingtools.run_sac_replay_replication()`／PowerShell `-ReplayRepeat`。
- 新 bundle `artifacts/packages/sac-replay-replication-20261118`，不重用第一輪 ledger；training seed 20261119，前輪 20261118。
- 50k／500k 各最多新增 100 回合、每臂一次 attempt、依序執行；相同 actor/critic LR、來源 SHA、評估 seeds 與 screening。共最多 120 次凍結評估。
- 兩組評估路線皆已看過，並非獨立 holdout；新 seed 不保證完全獨立噪音時序。兩臂完成後 paused，不自動續訓／升階。

驗證：MATLAB R2024b 隔離假引擎 `test_sac_actor_pilot('replay_replication')` 與原 `replay_retention` 都通過，核對 seed 傳入兩臂、容量、路線、100 回合預算、三份配對報告、完成重入不重訓、中斷拒絕重啟。log 在 `tests/output/replay-replication-flow.log`。PowerShell parser 無錯；隔離 fixture `-ReplayRepeat -PackageOnly` 產生 43 檔 ZIP，逐一核驗長度／SHA，RESULTS 含 12 列比較與已使用路線提醒。`git diff --check` 通過。

本次未修改 runtime 或 recovery／resize 算法，沿用前輪真實模型保存與 replay 保留驗證；未啟動正式訓練、飛行模擬或遠端連線，未證明新 seed 的實際結果。既有使用者 PPT／ZIP／筆記保持原位且未納入提交。

[執行、看圖、取消與補包](../guides/sac-replay-replication-2026-11-18.md)
