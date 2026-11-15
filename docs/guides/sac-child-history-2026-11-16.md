# 新child中間checkpoint凍結診斷

範圍固定為 `20261114_211021_recovery_tp4c32126b`，比較1600、1700、1800、1900、2000、2100；不是原來源run的同號checkpoint。這次只做評估與打包，不呼叫retry、啟動訓練、自動選分支或移動stage。

在遠端專案沒有活動訓練時，同步後執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1
```

新MATLAB程序以CPU無探索評估，每次最多3000步，Stage1無風／Stage2弱風各10條，seeds為2000011501–2000011510，與已交件1600、2100複核完全相同。這是已看過的診斷測試集，用來定位保存區間變化，不是新的獨立泛化證據。

先核對child paused、已保存2100／recovery_budget、model、parent lineage，以及每份checkpoint內的回合數與SHA。1600對應child初始checkpoint；2100使用Agent_Final，與已交件最終評估直接對應。

1600沿用舊cycle的`holdout_1600`，2100沿用`final_evaluation`：必須核對complete inventory的每檔SHA、checkpoint、環境／引擎／路線生成器／課程SHA、無探索設定、完整且唯一stage/seed配對。來源完整報告不存在時才補跑；已存在但損毀或不相符時拒絕，不偷偷替換。正常只新增中間四份、共80次飛行，最壞六份都要補測為120次。

資料放 `artifacts/packages/sac-child-history-20261116`。`review.json`記錄phase及已完成回合；`summary.json`與`RESULTS.md`比較跑滿數、實際有風子集與平均步數。保留每份evaluation.json、scenario與軌跡，可後續按相同時長檢查控制／偏離；不由RMS或reward單一數字推定根因。

重新執行同一指令會驗證並略過已完成項目；中斷的checkpoint批次可重跑，其原始報告保留。來源／程式SHA變動或交件損毀會拒絕混用。原run的暫停、guard、課程與模型不變，評估器只新增報告與暫存模擬資料。

若想完成目前checkpoint批次後停止，另一個PowerShell執行：

```powershell
New-Item -ItemType File -Force .\artifacts\packages\sac-child-history-20261116\CANCEL
```

結束或一般MATLAB錯誤退出後，wrapper會嘗試打包已產生資料，逐檔讀回驗SHA，最後顯示Verified ZIP與SHA256。ZIP只收本診斷資料夾，不含其他歷史run或訓練checkpoint。將ZIP與同名.sha256複製回本機根目錄。僅補打包可使用同一命令加`-PackageOnly`；若評估仍在執行會因鎖定拒絕打包。

## 本機驗證

R2024b `test_sac_child_history`使用隔離假checkpoint／假評估器，端點重用、僅四次新批次、中途1900錯誤後續跑、完成重跑略過、交件損毀拒絕皆通過。測試沒有train/sim/pool。Windows PowerShell5.1在該fixture執行PackageOnly，驗證RESULTS／2100報告存在、沒有訓練checkpoint、ZIP逐檔hash通過。真實80次飛行尚待遠端執行。
