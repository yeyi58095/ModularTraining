# SAC500k1700有界接續50回合

**此指令會訓練。** 從已通過兩批凍結評估的500k1700 final另建子run，最多50回合至1750，GPU6workers、一次attempt；之後80次CPU凍結評估、自動打包並paused，不自動續跑／升階。保留原來源與完整replay，LR／容量不變。來源337132筆加最多150000筆仍小於500k。

遠端這份副本沒有活動訓練時，在PowerShell貼上：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$ErrorActionPreference = 'Stop'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayExtend
if ($LASTEXITCODE -ne 0) { throw '接續或評估未完整完成，請貼回錯誤；不要自行 retry 或刪鎖。' }
Invoke-Item '.\artifacts\packages'
```

先核對來源SHA、兩批40/40報告、模型／GPU6設定與buffer，再建新run並執行。新回合應顯示1701–1750；正常結束後會評估1750（若提早正常停則評估實際保存回合），不代表再訓練一次。完成看到 `Verified ZIP` 後，把 `sac-replay-extension-*.zip` 與SHA交回；本機根目錄放好即可。

50回合限制的是訓練回合，不是50分鐘；另外有80次評估。不要同時在另一副本續訓，不在執行中pull。已完成重跑只打包；中途錯誤不自動重建或重啟。

## 即時訓練圖

等新分支開始Episode後，在另一PowerShell視窗：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$state = Get-Content '.\artifacts\packages\sac-replay-extension-20261119\review.json' -Raw | ConvertFrom-Json
$items = @($state.children)
if ($items.Count -ne 1) { throw '尚未建立唯一子run，稍後再開圖。' }
$session = $items[0].session
$model = Get-Content (Join-Path $session 'model.json') -Raw | ConvertFrom-Json
if ($model.name -ne 'sac_paper64' -or $model.experienceBufferLength -ne 500000) { throw '模型不符。' }
python .\tools\plot_training_rewards.py "$session" --watch 6 --view
```

## 正常取消與錯誤補包

想完成當前50回合保存後取消後續評估，在另一視窗：

```powershell
Set-Location 'D:\daniel\ModularTraining'
New-Item -ItemType File -Force '.\artifacts\packages\sac-replay-extension-20261119\CANCEL'
```

CANCEL只在安全邊界讀取，不強制打斷當前attempt／評估批次。不要用Ctrl+C當正常暫停；不要刪來源pause或ledger。若出錯，可補包目前證據，不再訓練：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayExtend -PackageOnly
```

[選擇此分支的證據、保留界線與測試限制](../records/sac-replay-holdout-result-2026-11-19.md)
