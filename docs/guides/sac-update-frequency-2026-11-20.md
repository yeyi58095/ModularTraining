# SAC 1700 更新頻率短對照

**下列指令會開始訓練。** 在實驗室以 PowerShell 開啟正式工作副本，並確認這份副本沒有其他活動訓練。目前實驗室 checkout 在 `I:\daniel\ModularTraining`。

```powershell
Set-Location 'I:\daniel\ModularTraining'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -UpdateFrequency
```

如果從另一台電腦接續，先在該機 checkout 根目錄 `git pull --ff-only`，並確認已有同一份來源 run 與其環境快照。工具從自身所在的 checkout 推導 run、輸出與暫存位置。GitHub 同步程式與紀錄，完整 run 依既有交接方式另行準備。兩份副本擇一執行。

## 這次會執行什麼

- 從同一份已核 SHA 的 SAC 1700 final 建立兩個 Stage 2 子 run。依序執行原值 `LearningFrequency=1` 與候選 `2`，各一次 attempt、最多 50 回合，每 50 回合保存。兩臂共用訓練 seed `20261127`，採 GPU／同步 6 workers 設定，保留 500k replay、原 actor／critic 學習率、環境和課程。
- 兩臂正常保存後，對凍結 1700 與兩臂終點各做 22 趟 CPU 評估，共 66 趟。十條固定新路線各跑無風與一種非零弱風。第 7 彎的診斷用 seed `2000012105` 另列。工具保存配對報告與軌跡，兩個子 run 停在保存邊界等待分析。
- `artifacts\packages\sac-update-frequency-20261121\review.json` 記錄狀態和兩個子 run。完成出現 `Verified ZIP`。更新頻率對梯度數的作用，以保存的梯度累計及實際互動步數核對。單一訓練 seed 與 50 回合上限只適合短對照。

## 看進度或在安全邊界取消

在專案根目錄另開 PowerShell 視窗。先讀當前狀態及分支，等 `status=training` 且 `current` 為相應的 `frequency1` 或 `frequency2`，再開該分支的即時圖。

```powershell
$state = Get-Content -LiteralPath '.\artifacts\packages\sac-update-frequency-20261121\review.json' -Raw | ConvertFrom-Json
$state | Select-Object status,current
$current = @($state.children | Where-Object { $_.label -eq $state.current })
if ($state.status -eq 'training' -and $current.Count -eq 1) {
    $session = $current[0].session
    if ([IO.Path]::GetPathRoot($session) -ne [IO.Path]::GetPathRoot((Get-Location).Path)) { throw '這份收據來自另一個磁碟。' }
    python .\tools\plot_training_rewards.py "$session" --watch 6 --view
}
```

圖上的紫色點線標示從 checkpoint 接續。最新子 run 的箭頭會顯示接續回合，兩邊平均窗口不同時也會列出各自設定。粗線使用各 run 日誌中的平均，背景細線是逐回合 reward。

要在已經開始的 attempt 或凍結批次完成後停止後續工作，建立 `CANCEL`。保留當前視窗，讓現有 attempt 正常保存。

```powershell
New-Item -ItemType File -Force '.\artifacts\packages\sac-update-frequency-20261121\CANCEL'
```

中斷或失敗時，可用 `-PackageOnly` 補包當前紀錄。已開始的程序失敗後，入口會保留 ledger 並拒絕直接再啟一次。單純準備使用 `-UpdateFrequency -PrepareOnly`。

[第 7 彎實驗日誌與配方依據](../records/sac-update-frequency-2026-11-20.md)
