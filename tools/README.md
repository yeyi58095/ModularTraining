# 專案工具

從專案根目錄呼叫；工具以自身位置推導專案根目錄，不依賴工作目錄判定根目錄。使用者傳入的資料路徑仍依各工具既有介面解讀。

| 工作 | 指令 |
| --- | --- |
| 模型與評估封存 | `python tools/training_artifacts.py --help` |
| 訓練曲線 | `python tools/plot_training_rewards.py --help` |
| 全部 SAC attempt／分支證據收集 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/collect_sac_evidence.ps1 -IncludeEvaluationTraces`；[範圍、預覽與交件](../docs/guides/sac-evidence-collection.md) |
| 本輪半速 SAC 自動評估／選擇／有界續訓 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_sac_review_cycle.ps1`；[規則、升階、取消與ZIP](../docs/guides/sac-review-cycle-2026-11-14.md) |
| 新child 1600–2100凍結回溯（不訓練） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_sac_child_history.ps1`；[端點重用、診斷與ZIP](../docs/guides/sac-child-history-2026-11-16.md) |
| 同一1600的actor LR短對照（會訓練） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_sac_child_history.ps1 -ActorPilot`；[兩臂各100回合與交件](../docs/guides/sac-actor-pilot-2026-11-16.md) |
| Actor短對照後的兩臂診斷（不訓練） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_sac_child_history.ps1 -PilotProbe`；[11/17決策與操作](../docs/guides/sac-actor-pilot-next-2026-11-17.md) |
| Pilot探索開／關比較（最多24次CPU模擬） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_sac_child_history.ps1 -ExplorationCheck`；[失敗情境診斷與交件](../docs/guides/sac-pilot-exploration-2026-11-17.md) |
| SAC64 replay保留對照（會訓練，各最多100回合） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_sac_child_history.ps1 -ReplayPilot`；[50k／500k配對、圖與交件](../docs/guides/sac-replay-retention-2026-11-18.md) |
| SAC完整收件版圖表 | `python tools/build_sac_collected_charts.py <intake-folder> --output <new-folder>`；[完整收件與驗證紀錄](../docs/records/sac-evidence-full-review-2026-10-27.md) |
| 精簡訓練報告 | `python tools/export_training_report.py --help` |
| 已知散落檔整理 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/organize_workspace.ps1` |
| 根目錄建置資料／快取整理 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/compact_workspace.ps1` |
| 暫停後編排收尾（含排他鎖） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/finish_workspace_layout.ps1 -SessionPath <run>`；套用加 `-Apply` |
| 按組別查找原始 run（本機資料夾捷徑） | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/link_experiment_groups.ps1`；預覽後加 `-Apply` |
| 其餘 PowerShell 工具 | `migrate_training_session.ps1`、`organize_training_reports.ps1`、`pack_training_diagnostics.ps1`、`preserve_training_environment.ps1` 均在本目錄 |

兩個整理工具預設僅預覽，`-Apply` 才移動。compact 將 `.meeting-build/` 移至 `output/meeting_training_20261014/build/`，根目錄 Python 快取封存至唯一 `artifacts/incoming/layout-*/root-python-cache/`。不刪除檔案；已有目的目錄、連結或 tracked 來源會拒絕。重跑已完成搬移不重複處理；中斷時依 manifest 找原位／目的地，不強制覆寫。

簡報建置資料先逐檔核驗，再更新 `.meeting-build` 和 Python 祖先路徑引用；原始腳本備份及修改前後雜湊在同一 receipt。未重建簡報；舊腳本既有的機器專用依賴仍須在實際重建前確認。正式簡報和 ZIP 保持原位。

Python 模組 `curriculum_progress.py`、`learning_health.py` 與 CLI 放在一起。跑測試可設定 `$env:PYTHONPATH=(Resolve-Path tools).Path`，再 `python -m unittest discover -s tests -p 'test_*.py'`；畫圖依賴見根目錄 requirements-plot.txt。

MATLAB 工具改用 `trainingtools.<原函式名>(...)`，詳見 [+trainingtools](../+trainingtools/README.md)。歷史紀錄中的舊根目錄指令不改寫；依此對照使用新入口。根目錄不保留同名轉接檔，以實際減少檔案數量。

SAC replay 第二個訓練 seed 複驗：`review_sac_child_history.ps1 -ReplayRepeat`，會新建兩臂各最多100回合；[指令、看圖與正常取消](../docs/guides/sac-replay-replication-2026-11-18.md)。`-PackageOnly` 僅補包。

SAC replay 新路線凍結評估：`review_sac_child_history.ps1 -ReplayHoldout`，80次CPU sim，不訓練；[指令與範圍](../docs/guides/sac-replay-holdout-2026-11-19.md)。

SAC500k1700接續50回合：`review_sac_child_history.ps1 -ReplayExtend`，會另建子run訓練並做80次凍結評估；[指令、看圖與取消](../docs/guides/sac-replay-extension-2026-11-19.md)。
