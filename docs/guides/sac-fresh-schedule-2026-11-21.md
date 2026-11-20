# 從零重跑 SAC 四段風況

此入口使用本機 MATLAB R2024b 與六個 Processes workers。從行程本身所在的 checkout 讀取設定。開始前既有更新頻率對照須到終止狀態，且兩個子 run 都已停止，避免兩組訓練搶資源。

```powershell
Set-Location 'I:\daniel\ModularTraining'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_sac_fresh_schedule.ps1 -Start
```

去掉 `-Start` 可先準備新 run 並核對快照。準備之後重跑相同入口會重用已核對的 run。執行開始後由 `schedule.json` 持續寫入保存證據。各階段上限 1000／400／300／300，第四段按配額正常保存與停止。每階段保存後執行原課程的凍結評估。若出現 guard 暫停、流程錯誤或有人要求停止，保留該狀態及原檔，再依證據處理。

另一個 PowerShell 視窗可讀收據，等 `training` 狀態出現再開即時圖：

```powershell
$state = Get-Content -LiteralPath '.\artifacts\packages\sac-fresh-schedule-20261121\schedule.json' -Raw | ConvertFrom-Json
$state | Select-Object status,current_stage,session
python .\tools\plot_training_rewards.py "$($state.session)" --watch 6 --view
```

建立 `artifacts\packages\sac-fresh-schedule-20261121\CANCEL` 可在當前有界段落結束後停止後續段落。需保留 MATLAB 啟動視窗或背景程序到安全邊界。分析使用 `schedule.json`、各段稽核目錄與保存 run，訓練中看圖的 reward 只代表當前日誌。

[排程依據及 meeting 證據](../records/sac-fresh-schedule-2026-11-21.md)
