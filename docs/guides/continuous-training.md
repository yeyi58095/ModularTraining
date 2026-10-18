# 明確啟用連續訓練

`configs/recovery_v2_18500_continuous.json` 是從 18500 checkpoint 建立新分支的歷史配方，不是已完成 39300 run 的下一輪啟動指令。本次同步不啟動訓練；下一輪從頭訓練與自動調整 learning rate 仍需另行設計。

恢復配方明確設定 `continuous_training: true` 與 `max_additional_episodes: 0` 時，prepare 只修改新分支：

- 所有階段 `on_limit` 設為 `continue`。到達 `max_episodes` 後仍等待原過關條件，不按預算強行換階段。
- guard 設為 `budget_enabled: false`、`regression_action: "monitor"`，保存邊界仍計算退步並印出警告，但不因此暫停；仍保存候選與 assessment。
- 每段 100 回合，`maxAttempts=0` 沿用無次數上限設定。最後階段過關仍正常成功結束；STOP、執行錯誤及既有已鎖定暫停仍可能中斷。
- actor LR 維持來源的 2.5e-5；不自動回滾、選分支、調 LR，也不保證收斂或一定能無人介入跑完。

未設定連續模式的配方仍有原預算及退步暫停。不要直接編輯既有 run 的課程或 guard 來解除暫停；prepare 保留父 run、checkpoint 與過關條件，新分支預設有 STOP，須明確 retry 才啟動。

2026-10-19 驗證：`test_curriculum`、`test_recovery_guard`、`test_continuous_training` 通過。使用合成歷史、既有測試 checkpoint、新建測試分支及假引擎，覆蓋超預算繼續、退步警告、原預算暫停、暫停鎖定、過關／完成與父檔案 SHA 不變；沒有執行 train/sim。Python 42 項測試通過。未驗證正式長訓練或 GPU／多 workers。
