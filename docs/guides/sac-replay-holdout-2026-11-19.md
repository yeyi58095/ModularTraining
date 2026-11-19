# SAC replay 新路線凍結評估

這次不訓練。比較來源1600與第二輪500k1700，20個新路線seed（2000011901–2000011920）、無風／弱風、關探索，最多80次CPU純sim。兩模型保持paused，沒有自動延長或升階。新路線相對兩輪replay pilot未使用，不代表已證明全面泛化或獨立風噪音時序。

遠端副本沒有活動訓練時，在PowerShell執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$ErrorActionPreference = 'Stop'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayHoldout
if ($LASTEXITCODE -ne 0) { throw '評估未完整完成，請貼回錯誤；不要刪鎖或自行重啟。' }
Invoke-Item '.\artifacts\packages'
```

先40次來源1600，再40次候選1700。畫面顯示Evaluating episode1600或1700是評估固定checkpoint，不是重訓那個episode。CPU評估需時間；已完成後重跑只打包。程式核對兩個指定checkpoint SHA、paused與paper64、先前screen通過、環境與配對風、40條完整結果，並輸出跑滿、步數與前10秒後原路線距離。

完成看到 `Verified ZIP` 後，交回 `sac-replay-holdout-*.zip` 與 SHA256；本機根目錄放好即可。RESULTS.md、comparison.json與兩模型評估軌跡皆在ZIP，沒有打包其他歷史run。全長3000步不等於完成路線或達到精度。

想完成目前一批40次評估後停止剩餘工作，在另一個PowerShell執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
New-Item -ItemType File -Force '.\artifacts\packages\sac-replay-holdout-20261119\CANCEL'
```

取消不會強制打斷當批sim。若意外中斷／錯誤，補包後交回，不刪ledger重跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ReplayHoldout -PackageOnly
```

[本輪結果、根因判讀與限制](../records/sac-replay-replication-result-2026-11-19.md)
