# Remote SAC pool failure and licensing recovery (2026-10-29)

## Outcome

使用者回報這是長期出現的問題第一次獲得具體解決。本次依下列授權資料重新取得流程處理後，交回 attempt 3 的實際輸出：`Connected to parallel pool with 6 workers.`、`Pool ready: 6 workers (requested up to 6, minimum 6).`，並完成前 6 個 episode，累計 554 steps。狀態為 running，attempt 啟動時間 2026-10-29T23:41:35+08:00。這確認本次已恢復建池並進入訓練，並非只通過 preflight。

附件仍顯示 Saved decision through Episode 0；尚不能宣稱第 100 回合 checkpoint 已成功保存、整晚穩定或學習已收斂。GPU 為原配方設定，這份 stdout 不構成 GPU 使用率或效能量測。遠端操作由使用者執行，代理未連線操作；未取得每個修復步驟的完整執行逐字紀錄，因此以下保留為本次提供的修復流程及其後收到的成功證據。

## Evidence and diagnosis

- Attempt 1：19:00:13 建池，約 13.84 秒後 PoolRunValidation／worker status 1；attempt 2：23:33:37 建池，約 7.50 秒後同類失敗。皆沒有完成 episode。
- 主 MATLAB、control.json 啟動路徑、clusterMatlabRoot 均為 R2024b；版本 24.2.0.3361896 Update 10。列出的安裝目錄只有 R2021b、R2024b；程序快照未見 R2026b MATLAB。
- Service Host 為 v2026.11.0.3；這是獨立更新的服務版本，不能直接當成 MATLAB 安裝版本或故障證明。
- Service Host client 日誌在 19:00:17、23:33:40 顯示 Error 5008 視窗，文字為 `You are not licensed to use R2026b.`，時間落在兩次建池失敗期間。
- service_20261029_8622／8623／8624 日誌則記錄 `errorcode: 5008`、`errormessage: Release not found in wallet`、`releasedesc: R2024b Update 10`。視窗版本與服務錯誤版本不一致，不能據此認定實際執行了 R2026b。
- 先前主程序有 onlinelicensing 及 MATLAB／RL／Simulink 等 checkout success；主程序授權成功不保證新 workers 啟動成功。獨立目錄單 worker 測試曾於 19:51 成功，也不能替代六 worker 訓練子程序驗證。
- 現有證據支持優先修復線上授權資料；並未確診資料損壞原因、Service Host 內部 bug、或所有歷史 worker crash 的共同根因。Copilot 元件版本描述也不是根因證據。
- 初版關鍵字搜尋誤將流水號中的 5008 當命中，且只查尾端可能漏掉錯誤；後續全文搜尋並使用數字邊界才取得有效證據。

## Reusable recovery procedure

適用於帳號確實有對應版本授權、但出現上述 5008／wallet 問題的情況；不是任何 parpool 失敗的通用修復。

1. 在 MathWorks 帳號確認授權涵蓋 R2024b，保持網路連線。
2. 確認訓練已 paused、保存其他工作後正常關閉所有 MATLAB。不要強制終止活動訓練。第一次執行下方檢查時仍有 MATLAB 程序，指令正確拒絕修改授權檔；先正常關閉再操作。
3. 在遠端 PowerShell 將使用者授權目錄內的 `.mwlicx` 改名備份，保留可恢復原檔，不刪除整個 licensing 或 ServiceHost 目錄。

```powershell
$ErrorActionPreference = 'Stop'
if (Get-Process -Name MATLAB -ErrorAction SilentlyContinue) {
    throw '請先正常關閉所有 MATLAB，再執行。'
}
$licenseDir = Join-Path $env:APPDATA 'MathWorks\licensing\licenses'
$files = @(Get-ChildItem -LiteralPath $licenseDir -File -Filter '*.mwlicx')
if ($files.Count -eq 0) {
    throw '找不到 .mwlicx；先停止，不修改其他檔案。'
}
$tag = [guid]::NewGuid().ToString('N')
foreach ($file in $files) {
    Rename-Item -LiteralPath $file.FullName -NewName ($file.Name + '.backup-' + $tag)
}
Write-Host '授權快取已改名備份，請連網重新開啟 R2024b。'
```

4. 重新開啟 R2024b，若要求登入，使用有授權的原帳號，讓授權資料重新取得。官方原流程為移除 `.mwlicx`；此處採改名保留備份。未提供刪除 license_info.xml、降版 Service Host 或重裝 MATLAB 作為本次操作。
5. 先驗證六 worker 建池，再恢復原 run；不重新 prepare、不刪 guard、不改課程快照。本次收到的成功證據是原 run attempt 3 的六 worker 實際訓練輸出。若同錯誤再次出現，保留備份、截圖與 Service Host 日誌交由 MathWorks 支援，不反覆刪其他授權資料。

授權快取含帳號相關資料，勿加入 Git 或公開分享；本紀錄只保留去識別化的錯誤摘要，不複製原日誌中的 token、授權編號或機器識別資訊。

## Sources and evidence scope

- [MathWorks 官方：版本授權錯誤及重新產生 .mwlicx](https://www.mathworks.com/matlabcentral/answers/1819030-why-do-i-receive-the-error-you-are-not-licensed-to-use-r20xxy-when-i-try-to-launch-matlab)
- [Service Host 獨立更新說明](https://www.mathworks.com/help/install/ug/what-is-mathworks-service-host.html)
- [Service Host 日誌位置](https://www.mathworks.com/matlabcentral/answers/101927-where-are-the-log-files-located-for-installation-activation-network-license-manager-and-the-servi)
- 使用者貼上附件：ce453d01-ff55-4901-9d9b-b78058768ee9（授權錯誤全文搜尋）；7fa96701-beaa-4ece-bd15-f996d8b68a3f（attempt 3 成功輸出）。附件識別只供本次對話追溯，不是遠端執行路徑或已提交完整日誌。

## Initial investigation (historical)

User-provided terminal evidence; no independent remote connection.

- Run: D:/daniel/ModularTraining/experiments/sac_random_route_v1/runs/20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580.
- R2024b, GTX1660 GPU build preflight passed; six process workers requested and required. First attempt paused after failure with no new checkpoint, zero completed episodes.
- pool_starting: Processes, job storage C:/Users/user/AppData/Roaming/MathWorks/MATLAB/local_cluster_jobs/R2024b; started19:00:13.
- pool_error: elapsed13.8380364s, parallel:cluster:PoolRunValidation; worker shut down unexpectedly with status1 during task execution.
- worker_attempts: ActualWorkers0, PoolReadyFalse, pool_start_failed, exit1, total83.2s (includes process startup/exit). Zero means no ready usable pool, not proof no worker process started.
- Prior stdout preserving jobs1/2 with crash dumps does not identify the current failed job or establish those dumps' timing.
- Not a learning regression, not proof GPU caused failure or RAM insufficient. Keep run/receipt and crash jobs; do not retry identical training or delete jobs before diagnosis.
- Follow-up attachment: storage exists, 66 files; latest listed files date2026-10-14 09:47, not this attempt. Job2 dump explicitly reports access violation at2026-10-14 09:47:06; stack includes Stateflow/Simulink libraries. c.Jobs lists Job1 failed and Job2 finished with task status-1073741819. These retained historical jobs do not explain the new status1 failure. Historical license-command warning also cannot establish today's cause.
- Initial next step (now completed/superseded): user-run single-worker pool-only diagnostic with fresh storage. Subsequent licensing investigation and successful attempt 3 are recorded above. No runtime code changed for this repair.

Reference: https://www.mathworks.com/help/parallel-computing/resolve-error-client-lost-connection-to-worker.html
