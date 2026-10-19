# 工作區整理與兩端同步

核心位置保持不變：根目錄是操作入口，`+training*/` 與 `+checkpointreview/` 是 MATLAB 套件，`runtime/` 是引擎，`environments/` 是環境版本，`experiments/<課程>/runs/` 保存實驗。程式依自身位置推導根目錄，不能任意將入口搬入 scripts。

資料分工：

| 位置 | 用途 |
| --- | --- |
| artifacts/incoming/ | 本機收到的診斷 ZIP、散落評估 JSON、截圖與備份；忽略 Git |
| artifacts/packages/ | Release 待上傳包與 descriptor |
| artifacts/results/ | 已下載、驗證的成果封存；不能直接續訓 |
| diagnostic_packages/ | 既有解壓資料與離線分析腳本，保留原位 |
| output/ | 現有簡報與交付物，這次不搬移或刪除 |
| tests/output/ | 可重建測試產物 |
| docs/records/ | 工作與驗證紀錄 |

新交付工作可在 output 下以任務分資料夾，將 build 中間檔與 dist 發佈檔分開；既有簡報仍依原忽略規則，不將修改或 ZIP 自動提交。舊 sessions、reports、trajectories 仍可能有相容性用途，不為目錄外觀搬動。

兩台電腦各自執行（專案根目錄 PowerShell）：

```powershell
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '請先處理 pull 錯誤，勿強制覆寫。' }
.\organize_workspace.ps1
# 確認清單後執行：
.\organize_workspace.ps1 -Apply
git status --short
```

預覽不改檔。Apply 只處理明列的根目錄診斷 ZIP、stage8_latest300.json、compare_training_checkpoints.m.backup_*，以及「新增資料夾」內 PNG；排除 tracked 檔，拒絕來源／目的地連結，不掃描 run，不搬 configs 內的備份或未知配方。每批新建唯一目錄，搬移前保存來源／目的地／SHA256／大小，搬移後核驗。中斷時依 manifest 查找原位及目的地；再次執行只處理仍在原位的檔案。沒有自動刪除或自動復原。

Git pull 同步工具與文件，不會替另一台電腦移動未追蹤資料。兩端資料量可以不同，目錄用途一致即可；實驗室簡報說明的本機修改保留，不用為了整理而 commit 全部檔案。

2026-10-19 本機先整理9個檔案，SHA256前後一致，manifest位於 artifacts/incoming/cleanup-20261019/manifest.json。實驗室是否完成須看其執行結果，不能由本機完成推定。

驗證：在獨立tests/output測試Git目錄，預覽不改檔、Apply搬移兩個指定檔並驗證manifest雜湊、tracked備份及未知檔保留、重跑不重複搬移；歷史AGENTS全文與整理前Git版本一致，新增入口連結存在，離線文件首頁已重建。這不是訓練測試，未啟動MATLAB。
