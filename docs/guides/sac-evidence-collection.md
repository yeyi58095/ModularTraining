# 一次收集 SAC 訓練歷程與圖表來源

用途：補齊 SAC+LSTM／純 SAC 的全部已存在 attempt 日誌、各分支設定、lineage、評估報告與繪圖來源。工具為 `tools/collect_sac_evidence.ps1`，Windows PowerShell 5.1 即可，不需 Python、MATLAB 或額外套件。

在有完整訓練資料的那台電腦，由使用者執行。代理不自行連線遠端。這個工具僅複製資料，不會啟停訓練、修改 control／guard／課程／checkpoint、不開模型、不操作 supervisor.lock、不移動或刪除來源。

## 直接執行

在遠端專案根目錄 PowerShell 執行。先按專案既有規則同步程式；如果仍有活動訓練，勿藉此更新 runtime。此工具本身可以讀取活動 run 的日誌。

```powershell
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，先處理 Git 狀態，不要強制覆寫。' }

# 預覽各 run、attempt 數量、來源大小與排除項目；不寫出檔案。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\collect_sac_evidence.ps1 -Preview -IncludeEvaluationTraces
if ($LASTEXITCODE -ne 0) { throw '預覽失敗，請回傳錯誤。' }

# 正式收集：包含已有的評估軌跡，仍排除訓練 checkpoint／replay。
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\collect_sac_evidence.ps1 -IncludeEvaluationTraces
if ($LASTEXITCODE -ne 0) { throw '收集失敗，不要傳 .partial；請回傳錯誤。' }
```

結尾顯示 `Verified ZIP: ...` 與 SHA256。將該 ZIP 放回本機專案根目錄並告知即可；依收件規則核對、分析、歸檔。ZIP 位置為 `artifacts/packages/sac-evidence/sac-evidence-<時間>-<隨機碼>.zip`，旁附 `.manifest.json` 和 `.zip.sha256`。重跑另建新檔，不覆寫舊包；驗證失敗的半成品保留 `.partial`，不發布成正式 ZIP。

## 收集範圍

- 掃描 `experiments/*/runs/*`、`+trainingmodels/*/runs/*`、`sessions/*`、`runtime/training_runs_parallel_checkpointed/*`，以 run 根目錄 `model.json` 的 `algorithm=SAC` 選取；若 algorithm 缺少，只接受明確 `sac_*` 模型名稱。不是取「最新一組」；PPO 不混入。
- 收集所有識別到的 SAC run，包含零 attempt 的 prepared 子run、有狀態的測試fixture與 `.preparing`（若已有有效 model.json）。manifest 列出原始狀態；收集到不代表它是正式訓練、準備成功或可續訓。
- 每個 run 遞迴保存所有未排除的檔案：所有 attempt 的 stdout／stderr、attempt／result／pool／process 診斷；supervisor 日誌、worker CSV、模型／環境／課程／guard／control／status／storage 設定、recovery、程式快照、JSON／CSV／圖片及其他小型證據。
- 評估 JSON、報表與圖表預設收；`-IncludeEvaluationTraces` 再包含 reports／evaluations 內符合 `ep*_stage*_seed*.mat`／`scenarios.mat` 命名的已存在軌跡。不會執行新評估。
- 一併收集 SAC 共用配方、收據、模型定義、相關工具／文件，以及 `artifacts/incoming/sac*` 與既有 root-intake SAC 子目錄的已解包證據。
- ZIP 內以 `evidence/<專案相對路徑>` 保持來源結構；manifest 列出每個 run、attempt 存在性、lineage、來源絕對路徑、檔案大小、排除理由及納入內容 SHA256。跨機舊 parent 絕對路徑保留原值，以 run ID 找本次已收父run；找不到或重名會標記，不猜測。

## 排除與完整性

預設排除訓練 MAT、既有 ZIP／RAR／7z、鎖檔、常見快取／產生物／dump。每檔上限 256 MiB；超限列於 manifest，不會靜默當成已收。目錄連結／junction 不跟隨；缺 model.json、無法解析 JSON、找不到父run等列為 issues。

若確認另需模型，可加 `-IncludeCheckpoints -MaxFileMB 0`（可能數十至數百 GB，會包含其他 MAT，也不代表完整可續訓備份）。既有壓縮包另加 `-IncludeArchives`。目前補繪圖只需上述 `-IncludeEvaluationTraces`，通常不需要這兩個選項。

活動run可以收，但這永遠是**逐檔快照，不是整組run的一致備份**。每檔讀取限制在開始複製時的長度，避免持續新增的日誌讓匯出無法結束；前後大小／修改時間變動會記錄 `changed_during_copy`。未觀察到 metadata 改變也不能證明內容從未改寫。所有已打包位元組都有 SHA，完成壓縮後逐檔讀回ZIP核驗才發布；這證明封包內容完整，不證明訓練狀態一致或已停止。

仍在寫入、被刪除或被獨占的來源可能導致失敗；不要刪 run 狀態或解鎖，回傳錯誤即可。若來源是 `.partial` 或評估本身未完成，也只是現有證據，不應當完成結果。

這個工具能補已有但尚未交回的日誌／圖表來源；不能找回從未記錄的 loss、被刪掉的歷史或尚未執行的評估。收集本身不代表已 Git 同步或可以直接 retry。
