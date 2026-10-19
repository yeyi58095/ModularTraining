# 配方索引

檔名與位置保持不變。此分類不是啟動授權；恢復配方須核對來源checkpoint、環境SHA與LR，不能因檔名較新就套用。

| 分類 | 檔案 | 用途 |
| --- | --- | --- |
| 現有八階段準備設定 | lab_gpu6_progressive_v2.json | progressive_v2、spatial_v2、最多6 workers＋GPU、start=false；不是已驗證的新一輪自動訓練控制器 |
| 舊六階段設定 | lab_gpu6.json | progressive_v1歷史入口 |
| 歷史恢復 | recovery_actor_half.json、recovery_startup_fix.json、recovery_11600_overnight.json | Stage3退步、初始化修正及延長 |
| 歷史恢復 | recovery_21600_endpoint_v2.json、recovery_31600_progress_window.json、recovery_33700_finetune.json | 環境修正與既有checkpoint分支 |
| 歷史v2恢復 | recovery_v2_18000_guarded.json、recovery_v2_18000_std_half.json | LR或探索倍率干預試驗 |
| 明確啟用連續模式的歷史配方 | recovery_v2_18500_continuous.json | 從18500建立新分支；不適用於將已成功39300當成新一輪從頭驗證 |

課程本身在 experiments/<課程>/curriculum.json；curricula/ 是通用範例。不要把硬體設定放進課程schema，或將上列恢復JSON直接當retry參數。未知本機配方與備份保留待辨識，不自動套用。
