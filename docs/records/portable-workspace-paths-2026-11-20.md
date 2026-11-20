# 實驗室外接碟與跨機輸出路徑

使用者指定實驗室的個人資料、程式與訓練成果以外接碟 `I:\daniel\ModularTraining` 為主。宿舍副本仍可從 GitHub pull 到 D:。MATLAB 安裝路徑獨立，執行程式透過當前 checkout 與操作的 run 推導資料位置。

- I: 原有 37 份 run control 記載舊 D: 的 runtime、session 和診斷位置。Supervisor 會在開鎖或寫檔前檢查 control 所屬位置，attempt 也會拒絕跨磁碟路徑。在本機對已搬移、確定停止的 run 執行 `retry(resume=...,start=false)` 時，會保留舊控制設定並將後續診斷放進本機 run。這次未批次修改既有控制或 run 快照。
- 比對 D: 與 I: 相同相對路徑的 model、environment、curriculum JSON 與 I: 停止狀態後，已重綁 I: 的 11 份 `artifacts/*run.txt`。本機備份 `artifacts/incoming/run-receipt-paths-20261120/` 含原收據及前後 SHA256。既有 evaluation ledger、checkpoint、lineage 和歷史報告保留原始來源。D: 的既有批次或副本無變更。
- 畫圖及精簡報告可讀取外部歷史來源，輸出須在當前 checkout 的磁碟。凍結評估、可寫入 run 的稽核與環境保存入口拒絕外磁碟目的。Simulink 專案快取使用本機忽略的 `artifacts/cache/`；作業系統與 MATLAB 安裝層的快取、個人設定及在另一個 checkout 執行的程式各自有原本的位置。

隔離測試包含 Windows PowerShell 過期路徑、外磁碟診斷、非本 run checkpoint、鎖持有人狀態保護及有效本機 STOP；遷移測試核對來源雜湊及目的控制；Python 驗證工具路徑與報告輸出；R2024b 測試相對／搬移 run、目錄相容性、課程與環境的假引擎流程。此次未啟動正式訓練、真實飛行或 GPU worker，未驗證 MATLAB 安裝層的系統暫存。
