# 第三組：新 agent 從頭驗證

Run：`20261019_164959_tpc77cb232_0370_4212_a632_e1644201eec0`。

八階段 progressive_v2、spatial_v2、ppo_lstm128。已收到建立 run 與環境驗證輸出；啟動指令已提供，尚未收到即時訓練狀態。不要因本頁未記錄啟動就重複啟動；先查原 run 狀態。

原始資料留在 ../../runs 的對應 run-id 下。執行群組捷徑工具後，從本目錄 runs/ 點入。

新 agent 使用目前基準模型：actor LR=5e-5、critic LR=1e-4，沒有恢復分支的額外探索 std 0.5 倍率或 recovery guard。不是完整複製前次成功分支的超參數；課程階段預算暫停仍保留。遠端實際配置以該 run 快照為準。

[第三組準備說明](../../../../docs/guides/round3-fresh-training.md)
