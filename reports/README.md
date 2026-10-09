# GitHub 精簡訓練紀錄

此目錄只追蹤 `<machine>/<session>/report.json`，例如 `lab/20260923_.../report.json`。
由根目錄 `export_training_report.py` 產生，不放 `.mat`、完整 stdout/stderr 或 CSV。
同一實驗更新同一檔案，避免每次匯出新增一份；Git 歷史仍會累積，建議在異常或重要里程碑時更新。

```powershell
python export_training_report.py "+trainingmodels/ppo_lstm128/runs/實驗資料夾" --machine lab
```

只需 Python 標準函式庫，不需 MATLAB 或 matplotlib。資料可以來自活動中的實驗，匯出只讀檔，不控制訓練。
在宿舍執行時改成 `--machine dorm`。標籤由使用者指定，不代表工具已驗證執行主機。
對舊版 Simulink 實驗可指定完整路徑；若診斷在外面，另外加 `--diagnostics "診斷資料夾"`。
匯出器不自動讀取 `control.json` 裡的舊絕對路徑。

預設至多 400 個區間摘要、最近 100 筆 episode、最近 200 個 attempt 與 worker 摘要；全期事件／worker 計數保留。
包括 reward 的最小／最大／平均、episode steps、Q0、最佳連續 50 回合平均、缺回合與重複行統計。
若想放大圖中異常區間：

```powershell
python export_training_report.py "實驗資料夾" --machine lab --from-episode 170000 --to-episode 190000
```

這只調整 `focus.windows` 的區間；全期摘要與最後 100 回合仍保留，同一 report.json 會更新。
檔案超過 1.5 MB 時拒絕寫入。只複製允許的數值設定、已知狀態與事件類別，不複製原始錯誤文字、PID、主機名稱或設定中的絕對路徑。
實驗目錄名稱、使用者指定的機器別名、程式相對檔名與 SHA-256 仍會出現在報告中。

`saved_model_source_sha256` 對應實驗的模型快照；`current_checkout_sha256` 只代表匯出當下的程式，不能證明舊實驗實際使用它。
匯出不是原子快照；新寫入的日誌／worker CSV 可能跨時間點，JSON 的 warnings 與 limitations 需一起閱讀。
重複 episode 用較新 attempt 覆蓋，並未驗證 checkpoint 血緣；曾跑過但未存檔的 episode 也可能留下。
詳細錯誤堆疊、逐回合全資料與 checkpoint 仍留在原電腦，需要時再針對指定區間分享。

匯出後可檢查 `git status --short` 與 `git diff -- reports/`，再由使用者決定 commit／push。
這個資料夾不能用來續訓；checkpoint 搬移是另一項操作。
