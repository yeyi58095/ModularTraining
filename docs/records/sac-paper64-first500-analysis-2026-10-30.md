# SAC paper64 首段 500 回合與接續初期分析

2026-10-30，依使用者交付的兩份遠端 stdout 副本分析；未連線遠端、未啟停訓練、未修改設定或模型。不是即時狀態。

## 身分、保存與接續

- 兩檔皆明寫 model=sac_paper64、SAC、LSTM units=0、Stage 1/4 random_calm、v7，來源為 `D:/daniel/ModularTraining/experiments/sac_random_route_v1/runs/20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580`。
- paper1_stdout.log 包含完整 Episode 1–500，最後累計 946640 steps，六 workers ready，正常停止／保存訊息及 `Attempt finished: episodes=500, trailing mean=1977.1684, success=0`。
- paper2_stdout.log 明寫 Loaded agent: 同 run 的 Agent_Final.mat、Continuing with episode 501；再次六 workers ready，包含 501–512，累計 972341 steps。兩檔共 512 個連續、不重疊 episode。
- 相較先前僅六回合證據，本次確認「stdout 報告首段正常保存，下一程序成功載入並接續」。未收到 MAT 或 result.json，不能另聲稱已核對 checkpoint SHA、全部每100回合檔案或 optimizer 私有狀態。
- 檔名 paper1／paper2 是使用者交付命名，不是原 attempt 編號；第一份開頭與先前 attempt 3 一致，但檔案本身未印 attempt ID。success=0 是未完成成功判定，不是本段 crash。
- 舊 Job1／2 crash 保留警告在兩段均出現，但兩段隨後皆成功六 workers 建池，不能把這個警告當成新的失敗。

## 從已輸出的逐回合數值重算

Reward 由 stdout 的兩位小數重算；steps 為整數。每100回合區塊互不重疊，最後12回合不是完整視窗。

| Episode | 平均 reward | 平均 steps | 跑滿3000步 |
|---|---:|---:|---:|
| 1–100 | 228.20 | 307.43 | 0/100 |
| 101–200 | 1226.19 | 1631.63 | 22/100 |
| 201–300 | 1903.09 | 2389.24 | 62/100 |
| 301–400 | 2100.50 | 2611.88 | 74/100 |
| 401–500 | 1974.51 | 2526.22 | 66/100 |
| 501–512 | 1647.36 | 2141.75 | 6/12 |

已輸出100回合移動平均最高為 Episode405 的2118.99；Episode512為1943.19，較峰值低約8.30%。末100回合（413–512）在即時課程列中為平均2491.11步、滿長率66%。

前400回合的 reward、steps、滿長率共同改善，支持訓練表現確實進步。401–500 相較301–400，reward下降約6.00%、滿長率由74%降至66%；宜描述為改善後平台與局部回落，尚非已證明持續崩落。501–512只有12筆，不能拿其平均直接當成另一個完整100回合視窗。每回合路線及探索可帶來變動；目前未收到路線seed／終止原因／軌跡與凍結評估，不能分辨路線難度、探索或策略退化的各自影響。

回落在500之前已出現，不能說是接續才造成；也不能憑這些資料排除接續影響。3000步只表示跑滿本環境回合上限，不等於完成整條路線或距離誤差已達標。

注意：末段 summary 的 trailing mean=1977.1684 與 Episode500 日誌100回合平均1974.51不同，差異超出簡單兩位小數捨入可解釋範圍。本分析保留兩者、不混用；缺少保存後訓練統計及 outcome 原始檔，尚未定位差異原因。正式課程決策以保存狀態為準。

## Stage 1 與剩餘時間

Episode512 即時列仍未達：最低1000回合、reward mean2200、steps mean2800、滿長率90%，且後三項須各連續3個100回合視窗。與末100回合相比，reward差256.81、steps差308.89、滿長率差24個百分點；不能預告第1000回合必定升階，另有凍結評估門檻。

第二段預定上限1000，交付快照尚餘488回合；其他停止條件可提早結束。兩份 stdout 沒有逐回合時間戳、attempt duration 或此次開始時間；本機檔案修改時間可能只是複製時間，不能據此算秒／回合。先前23:41:35啟動紀錄到這次交件的跨度也不能可靠當純訓練耗時。因此目前不能確認是否晚上才跑完，不提供虛假的完工時間。

現階段依使用者要求只分析，等待目前 attempt 正常結束。兩份 stdout 不包含 control.json，不能獨立核實段末暫停設定已寫入。未要求使用者現在做額外操作。後續有完整狀態／worker_attempts.csv／checkpoint統計再更新保存、耗時與末段表現。

## 歸檔與來源

兩份檔案由本機專案根目錄移入 `artifacts/incoming/sac-paper64-first500-20261030/`，來源路徑、長度、原修改時間與 SHA256 留於該目錄 provenance.json。搬移前後 SHA256 一致，未修改檔內遠端路徑；這是外來日誌副本，未移動活動 run。

- paper1_stdout.log：223368 bytes，SHA256 `CF0C8848FB58D1BCD530A831377DD86D4FE388FAE4505CDB182E927FEDFB0F20`。
- paper2_stdout.log：6725 bytes，SHA256 `E0BB0C87519DB618D1A3780BD228282F07759FDA6AFA322002FD64E8DEBD4539`。

完整日誌與 provenance 留本機，不加入 Git；僅本摘要及狀態入口同步。歸檔不代表取得可續訓的完整 run。
