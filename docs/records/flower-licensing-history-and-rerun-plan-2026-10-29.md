# Flower 授權歷史、下次 meeting 素材與原版重跑構想

日期：2026-10-29。依使用者要求唯讀查找 Flower；未修改來源、未啟動訓練、未製作或修改簡報。Meeting 預計數週後再準備，本文件保留可直接使用的報告素材與待辦。

## 查到的歷史證據

來源根目錄：`D:/daniel/GradSchool/0-Beginner/Paper/Flower`。

| 來源（相對 Flower） | 位置 | 可支持的事實 |
|---|---|---|
| PaperReport/研究進度日誌_2026-09-23.md | 第 21、29 行 | 09/22 已記錄目標 6 workers 無法完成啟動、授權錯誤與逾時；建立 6→4→2 備援，明確說明降級不代表授權問題已修好。 |
| Deep Reinforcement Learning/Simulink/CHECKPOINT_TRAINING_README.md | 第 85–90 行 | 已有授權錯誤等待與重試；可識別 5008／You are not licensed to use R20XXy／License checkout failed；只彈窗而未寫入 log 時靠 timeout 處理。文件明寫重試不會修復缺少授權。 |
| Deep Reinforcement Learning/Simulink/checkpoint_watchdog.ps1 | 第 5–6 行 | 實作 5008 與版本授權字樣的偵測，回傳 license_error。這是防護程式，不是某次錯誤確實發生的逐次事件證據。 |

歷史日誌自述日期為討論／觀察日，不一定是首次發生時間。此次搜尋 Flower 的 md/txt/log/json/m/ps1 文字資料，未找到明確記錄「R2024b 執行時彈 R2026b」的舊事件；不宣稱已證明九月與十月完全相同根因。也不能把九月的 Access violation、訓練卡住或 reward 下降全部歸因於授權。

本次讀取來源 SHA256（按上表順序）：

```text
42F55D3CC8F72D8942B7520E6D381E0D68178E104DBDF19F6521EE52BF571C1A
EDC652EF4EB3A57B8475DA4AD55CDFA1526EE703F9A4E0EE200B7C3B7CE0EB95
4A264B39083C6D28D27109773A8BB21E9FBE2AE2AB3D9FE6F141FC184971FD5D
```

## 下次 meeting 可報告的內容

建議主題：**從長期平行啟動問題，到取得授權錯誤證據並恢復六 worker 訓練**。

1. 背景：至少九月已有六 worker 建池／授權問題，當時增加重試、備援 workers 與 checkpoint，提高可恢復性，但沒有修好授權本身。
2. 本次定位：10/29 兩次建池失敗，服務日誌出現 5008、Release not found in wallet、R2024b Update 10；彈窗顯示 R2026b，與實際版本不一致。
3. 處理：依官方方向，確認有效授權，關閉 MATLAB，將 .mwlicx 改名備份，連網重開以重新取得授權。完整步驟見[修復紀錄](sac-random-pool-failure-2026-10-29.md)。
4. 驗證：原 SAC run attempt 3 已連線六 workers 並完成前六回合／554 steps。這是修復後實際進入訓練的證據；尚不代表長期穩定、checkpoint 保存或收斂已完成驗證。
5. 後續：在授權問題排除後，重新評估花花原版訓練，區分基礎執行環境與演算法／環境修改造成的差異。

可直接講的版本：

> 這個平行啟動問題其實在九月 Flower 的研究紀錄裡就出現過，當時主要靠重試和降低 worker 數處理。這次我們把 MATLAB 建池時間和授權服務日誌對起來，找到 5008 與 Release not found in wallet；雖然程式是 R2024b，視窗卻顯示 R2026b。依官方方式重新取得本機授權資料後，六個 workers 已成功啟動並開始 SAC 訓練。這是首次取得這麼具體的處理與恢復證據，但不能因此認定過去所有 crash 或 reward 下降都來自同一原因。接下來希望確認學長原版來源，再看它在修復後的環境中會怎麼訓練。

待補圖表：5008 視窗、去識別化的 wallet 錯誤節錄、六 worker 成功輸出、後續 checkpoint 與 GPU 遙測。原日誌中的 token／帳號／授權編號不放簡報。

## GPU 現場觀察

使用者於本次成功開始訓練後回報：**「這是我第一次看到 GPU 如此頻繁地被使用。」** 已作為重要現場觀察保留；目前沒有 GPU 使用率時間序列或量測截圖，不能換寫成平均使用率提高多少、加速幾倍或 GPU 首次真正運作。

現有成功證據為 GTX1660 配方下的六 worker 訓練 stdout。後續可在不干擾活動 run 的前提下收集 GPU 使用率、顯存、功耗與時間戳，對照 episode／更新／checkpoint 時間；如要比較效能，需固定硬體、模型、worker 數、任務與量測區間。GPU 活動增加不等於學習品質提升，也不能單獨證明由授權修復造成。

## 未來花花原版重跑：保留為待辦，尚未啟動

使用者希望在本次問題排除後，重新跑花花原本程式，觀察訓練曲線與行為；原因是過去已大幅修改花花程式。此次表達為未來實驗意向，不是立刻啟動訓練。

- 先確認「學長交付原版」來源：目前 Flower 中已存在 checkpoint／autoretry／ModularTraining 等後續檔案，不能把整個當前 Flower 資料夾直接叫做未修改原版。需比對原始交付檔、備份或可追溯版本，保存入口、SLX、路徑產生器及設定的 SHA256 與差異；無法證明時明稱候選版本。
- 來源唯讀保存，未來在獨立實驗副本與新 run 從頭初始化 agent，不覆寫 Flower，不接目前 SAC checkpoint，不與目前活動 run 同時搶用資源。
- 原版基準保留其模型、reward、觀測、動作、路徑／風場、終止條件和訓練超參數；不能默默套用本案 spatial_v2 或 SAC paper64。若需新增保存／監測包裝，列明與原版的差異及其可能影響。
- 先做有界建池與短程保存檢查，再由使用者在遠端執行明確預算的完整試驗；記錄 MATLAB／Service Host／GPU／實際 workers、seed、來源版本、錯誤與 checkpoint。
- 同時看 reward、steps、終止原因、固定條件凍結評估、GPU／CPU 活動與耗時；不同 reward／環境的 Flower 與現行 SAC 分數不能直接作學習優劣比較。
- 先回答「原版能否穩定跑、曲線如何」，若之後要比較改版效果，再建立條件一致的對照；單次修復後重跑不能追溯證明過去性能差異由授權造成。
