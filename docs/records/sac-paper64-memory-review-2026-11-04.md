# SAC paper64：1186回合曲線與資源錯誤初步分析

分析日期2026-11-04，來源是使用者交付CSV與training_status文字，不是即時遠端監控。未啟停訓練、未改runtime／課程／run快照。

## 結論與進度邊界

同run `20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580`，attempt5，state=error，更新時間2026-11-01T07:19:38.9528714+08:00，訊息「記憶體資源不足，無法完成此作業。」stdout最新1186，2618813累計steps，Stage1 random_calm。Saved decision through Episode1000不是最後checkpoint檔案清單；不能由此斷言1100沒保存，也不能認定1186可恢復。需核對checkpoints檔案與可讀性，未提供resume指令。

使用者確認遠端96GB RAM。這不排除Windows提交記憶體上限、個別程序／系統資源不足、GPU顯存或其他資源問題；目前沒有耗用量、錯誤識別碼或堆疊足以分類。不是已確診RAM耗盡、GPU OOM或memory leak，也無證據說這次與之前5008授權問題相同。

## CSV驗證與統計

1186列，episode恰為1–1186無重複或缺號，各列total_steps與steps累加完全一致。attempt3=500列、attempt4=500列、attempt5=186列。最新CSV與貼上stdout的1186數值一致。CSV為console輸出精度，不是MAT原始浮點統計。

| 回合 | 平均reward | 平均steps | 滿3000步數／樣本數 |
|---|---:|---:|---:|
| 1–100 | 228.20 | 307.43 | 0/100 |
| 101–200 | 1226.19 | 1631.63 | 22/100 |
| 201–300 | 1903.09 | 2389.24 | 62/100 |
| 301–400 | 2100.50 | 2611.88 | 74/100 |
| 401–500 | 1974.51 | 2526.22 | 66/100 |
| 501–600 | 1995.20 | 2492.04 | 69/100 |
| 601–700 | 1860.39 | 2348.98 | 57/100 |
| 701–800 | 1952.06 | 2453.02 | 65/100 |
| 801–900 | 1982.56 | 2469.79 | 70/100 |
| 901–1000 | 2020.91 | 2522.46 | 65/100 |
| 1001–1100 | 1783.22 | 2256.13 | 53/100 |
| 1101–1186（86筆） | 1995.28 | 2534.08 | 57/86 |

第405回合的100回合移動平均2118.99仍為CSV最高；最新末100回合1087–1186平均1973.9035、2506.06步、66%滿長，其中12回合少於1000步。滿長不是完成整條隨機路線，也不是誤差達標。

501–1000整段平均1962.22、2457.26步、65.2%滿長；1001–1186平均1881.27、2384.65步、59.14%滿長，但後86回合已有回升。支持「前期學習後進入波動平台、短回合仍反覆出現」，不支持持續單向崩落的強結論。1001開始一度較差，仍不能只憑接續邊界認定重啟造成退化；缺路線seed／終止原因／凍結評估，無法分開隨機路線難度、探索與策略變化。

最低1000回合已達，末100回合reward還差226.10、steps差293.94、滿長率差24百分點，三項均要求連續3個100回合視窗。尚未通過Stage1，不能因為已跑1186回合而升階。資源錯誤與未過訓練門檻是兩個不同問題。

## 為什麼96GB仍需查系統資源

Windows提交上限與實體RAM及pagefile有關，不能只看安裝容量；六個process workers加訓練主程序及其他應用的耗用需合看。GPU顯存另算，96GB系統RAM不是96GB顯存。上述均是排查方向，非本次根因證明。

本機目前程式 `runtime/checkpoint_supervisor.ps1` 外層catch把 `$_.Exception.Message` 寫為state=error，再於finally嘗試清理所屬程序；這種status形式與supervisor例外相符。監控內包含程序查詢、診斷與日誌操作，故可能是監控端先失敗再引發訓練中止，不能只看最後一個Episode就判定MATLAB自身OOM。沒有遠端程式SHA及堆疊，僅為依現有程式的定位線索，未指定某行為根因，也不能假設清理已成功。

目前sac_paper64定義僅雙64層、actor4994參數與兩個各4993參數critic；replay容量50000，不能把累計261萬步當成全部留在replay。以10維觀測、1維動作、double數值粗算每筆兩個觀測加動作／reward／done為23*8bytes，50000筆約9.2MB（十進位）；這只是純數值下界，不含物件、梯度、複製、Simulink模型／日誌／worker等成本，不能當成實際RAM估算。本機training_engine設定SimulationStorageType=none，也不能排除其他Simulink訊號／原生庫占用。由此不宜先盲目縮batch／replay或購買更多RAM。

## 下一步取證（遠端由使用者執行）

先看attempt_00005的stderr.log、result.json、現有checkpoint清單及diagnostics/worker_attempts.csv，再查2026-11-01 07:19附近Windows System的Resource-Exhaustion-Detector Event2004。若存在，內容可提供當時主要記憶體消耗程序；沒有事件不排除資源問題。目前的記憶體／pagefile快照只能說明現在，不能代替故障時狀態。

在證據到齊前不直接retry、不降低終止／課程門檻、不刪鎖。之後若確認整體提交量不足，才討論pagefile與其他程序；若某worker隨時間增加，才設計有界記憶體監測、縮段／減worker對照；若GPU OOM需GPU堆疊與顯存數據；若supervisor自身問題，應補例外堆疊與HResult診斷再修復。未在本次修改執行程式。

參考：[Microsoft提交上限與pagefile](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows)、[資源耗盡Event2004](https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/troubleshoot-application-service-memory-leaks)、[MATLAB記憶體診斷](https://www.mathworks.com/help/matlab/ref/memory.html)。

## 歸檔

本機根目錄CSV已移至`artifacts/incoming/sac-paper64-memory-20261104/`，來源與目的地及SHA在provenance.json，搬後雜湊一致。貼上狀態副本為status-user-paste.txt；不修改內容中的遠端路徑，不搬活動run。完整資料不加入Git，僅提交摘要。

- CSV SHA256：4210E3B7FCA1D8854A1BDB575973DACAD38833165D7A3C94ECF2136C0C2AEF11。
- 狀態附件SHA256：3A20D188116A5BAE25FCB0E0168B3BE5AEA1989DDB571CCCC6A26E4923897A79。
