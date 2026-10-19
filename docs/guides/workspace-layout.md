# 工作區整理與兩端同步

核心位置保持不變：根目錄是操作入口，`+training*/` 與 `+checkpointreview/` 是 MATLAB 套件，`runtime/` 是引擎，`environments/` 是環境版本，`experiments/<課程>/runs/` 保存實驗。程式依自身位置推導根目錄，不能任意將入口搬入 scripts。

資料分工：

```text
ModularTraining/
├─ README.md / retry.m          查找入口／訓練入口
├─ +training*/                 MATLAB 套件
├─ runtime/                    執行引擎
├─ environments/               版本環境
├─ curricula/                  課程範例與模板
├─ configs/                    準備／恢復配方（見分類 README）
├─ experiments/
│  ├─ README.md                全部已登錄課程成果
│  └─ <課程>/
│     ├─ README.md             課程首頁
│     ├─ curriculum.json       目前課程定義
│     ├─ assets/               該課程輸入資產（若有）
│     ├─ runs/<run-id>/         原始實驗，保持原位
│     └─ completed_models/
│        ├─ README.md          完成模型清單
│        └─ <run-id>/
│           ├─ README.md        結果、限制、歷程完整度與下載方式
│           ├─ provenance.json  來源與模型 SHA256
│           └─ Agent_Success.mat 本機模型，Git 忽略
├─ artifacts/                  本機收件、封裝、下載與已核驗成果
├─ docs/                       操作、研究與紀錄
├─ output/                     簡報及交付物
└─ tests/                      驗證與可重建產物
```

這次統一查找入口及成果分類，不搬既有 runs、sessions、diagnostic_packages 或根目錄執行工具。歷史資料仍保留原來的相容路徑。後續每個完成模型另建成果目錄；登錄規則見 [成果索引](../../experiments/README.md)。

| 位置 | 用途 |
| --- | --- |
| artifacts/incoming/ | 本機收到的診斷 ZIP、散落評估 JSON、截圖與備份；忽略 Git |
| artifacts/packages/ | Release 待上傳包與 descriptor |
| artifacts/results/ | 已下載、驗證的成果封存；不能直接續訓 |
| experiments/<課程>/completed_models/ | 課程內的成果入口；README 與 provenance.json 隨 Git 同步，MAT 留在本機／Release，不代表完整可續訓 run |
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

## 本次遠端更新與模型下載

先確認該副本沒有活動訓練，再在實驗室專案根目錄執行。若專案仍位於 `D:\daniel\ModularTraining`，可先 `Set-Location -LiteralPath 'D:\daniel\ModularTraining'`；實際位置不同請替換。

```powershell
git status --short
git branch --show-current
# 本次提交在 main；確認目前也是 main 再執行：
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '更新失敗，請保留本機修改並貼回錯誤。' }
.\organize_workspace.ps1
# 預覽內容正確時，再執行 .\organize_workspace.ps1 -Apply
```

若 pull 因本機修改或同名未追蹤檔停止，保留原件並先釐清差異，不使用 reset --hard、clean 或強制覆寫。既有簡報修改不需為了這次更新一併提交。

若也要讓另一台的課程資料夾有模型本體，可執行下列步驟。它從已核驗封存複製，不覆寫已有不同模型：

```powershell
python training_artifacts.py sync --tag "result-20261017_071436_recovery_tp323769ed-e177d217bc1f"
if ($LASTEXITCODE -ne 0) { throw '成果下載或驗證失敗。' }
$modelFolder = 'experiments/progressive_v2/completed_models/20261017_071436_recovery_tp323769ed'
$modelSource = 'artifacts/results/result-20261017_071436_recovery_tp323769ed-e177d217bc1f/Agent_Success.mat'
$modelTarget = Join-Path $modelFolder 'Agent_Success.mat'
$modelExpected = (Get-Content -Raw -LiteralPath (Join-Path $modelFolder 'provenance.json') | ConvertFrom-Json).sha256
if ((Get-FileHash -LiteralPath $modelSource).Hash -ne $modelExpected) { throw '來源模型 SHA256 不符。' }
if (Test-Path -LiteralPath $modelTarget) {
    if ((Get-FileHash -LiteralPath $modelTarget).Hash -ne $modelExpected) { throw '已有不同模型，保留原件。' }
} else {
    Copy-Item -LiteralPath $modelSource -Destination $modelTarget
}
if ((Get-FileHash -LiteralPath $modelTarget).Hash -ne $modelExpected) { throw '目的模型 SHA256 不符。' }
```

上述操作不啟動訓練，也不讓成果目錄變成可直接續訓的 run。

2026-10-19 本機先整理9個檔案，SHA256前後一致，manifest位於 artifacts/incoming/cleanup-20261019/manifest.json。實驗室是否完成須看其執行結果，不能由本機完成推定。

驗證：在獨立tests/output測試Git目錄，預覽不改檔、Apply搬移兩個指定檔並驗證manifest雜湊、tracked備份及未知檔保留、重跑不重複搬移；歷史AGENTS全文與整理前Git版本一致，新增入口連結存在，離線文件首頁已重建。這不是訓練測試，未啟動MATLAB。
