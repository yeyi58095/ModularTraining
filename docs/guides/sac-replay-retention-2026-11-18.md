# SAC64 replay retention 有界訓練

這條指令**會訓練**：從已保存且核SHA的Agent1600各建新分支，比較replay50k與500k，兩臂依序各最多100回合，沒有自動長跑／升階。這是機制假說試驗，未證明修復。不接續舊1700或2100。

遠端這份副本沒有其他活動訓練時，在PowerShell貼上：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$ErrorActionPreference = 'Stop'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayPilot
if ($LASTEXITCODE -ne 0) { throw '試驗未完整完成，請貼回錯誤；不要自行 retry 或刪鎖。' }
Invoke-Item '.\artifacts\packages'
```

程序順序：

1. 核對source paused、模型／環境／checkpoint與GPU六worker設定，來源1600凍結評估40次。
2. 新50k基準組：最多100回合，保存到1700後正常paused，再40次凍結評估。
3. 從相同1600另建500k候選：相同LR及其餘設定，最多100回合；核對原50k是否完整保留，再40次凍結評估。
4. 自動輸出comparison.json、screening.json、準備／訓練後replay audit、訓練紀錄、模型與評估軌跡，打包並驗證ZIP。

兩段都顯示1601–1700，因為是不同分支，不是重複續跑同一run。基準用新training seed20261118重跑，用來避免只拿舊seed的失敗對照新候選。整套包含最多200訓練回合與120次凍結模擬，可能需數小時；沒有可靠精確完工估計。過程中不pull更新、不讓電腦睡眠、不在另一副本同時續訓。

結果在 `artifacts/packages/sac-replay-retention-20261118/`，交回 `sac-replay-retention-*.zip` 與SHA，放本機根目錄即可。screen_pass僅是值得複驗的篩選，不能當成已通過原Stage3門檻。這一輪兩臂最多到Stage2第700回合，原1000回合最低門檻仍不足，不強行升階。

若希望完成目前有界工作後取消剩餘工作，在**另一個PowerShell視窗**執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
New-Item -ItemType File -Force '.\artifacts\packages\sac-replay-retention-20261118\CANCEL'
```

CANCEL不強制中斷當前attempt或當批評估，會等保存／批次結束後停止後續工作。不要用Ctrl+C當正常暫停方式，不刪review.json、CANCEL或run鎖繞過保護。發生錯誤後可用以下命令補包部分證據，不會再啟訓練：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayPilot -PackageOnly
```

## 另一視窗看目前訓練圖

等畫面開始顯示新分支Episode後執行（切換到第二臂時需重開此命令，圖不會自動跳分支）：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$state = Get-Content '.\artifacts\packages\sac-replay-retention-20261118\review.json' -Raw | ConvertFrom-Json
$item = @($state.children | Where-Object { $_.label -eq $state.current })
if ($item.Count -ne 1) { throw '目前尚未建立訓練分支，稍後再開圖。' }
$session = $item[0].session
$model = Get-Content (Join-Path $session 'model.json') -Raw | ConvertFrom-Json
if ($model.name -ne 'sac_paper64') { throw '模型不符。' }
python .\tools\plot_training_rewards.py "$session" --watch 6 --view
```

本機已驗證準備／保存／buffer資料保留與假引擎流程，未代替遠端啟動訓練；細節見 [結果與試驗設計](../records/sac-pilot-exploration-result-2026-11-18.md)。
