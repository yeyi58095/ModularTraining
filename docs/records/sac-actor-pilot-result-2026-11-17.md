# SAC actor 短對照交件 — 2026-11-17

已核對根目錄 `sac-actor-pilot-20261117-034358-33585671.zip`，SHA256 `2243D9CA1FAF90FBE9D1AC72087DC4B598DCAA26D579298D07BDE7E1F28F48ED` 與使用者遠端輸出一致，177 個 manifest payload 的長度及 SHA 全部通過。歸檔至 `artifacts/incoming/sac-actor-pilot-20261117/`，解包在 `payload/`，原路徑與 hash 在 `provenance.json`。搬移時首次因本程序尚開啟 ZIP 而僅完成複製，關閉後再次核對兩檔 SHA，再移除根目錄同一來源檔；未覆寫目的檔或更動 run。

## 已完成的訓練與凍結比較

`review.status=complete`，兩臂各新增100回合、正常保存1700，`recovery_budget` paused，皆留在 Stage 2。不是 Ctrl+C 中斷，也不是升階成功。

來源為 `20261114_211021_recovery_tp4c32126b/checkpoints/Agent1600.mat`，SHA `45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c`。兩臂請求相同 seed 20261116、GPU/6workers、critic LR3e-4、replay50k，actor LR分別1.5e-4及7.5e-5。

| 模型 | 新增訓練步數 | 全100回合平均reward | 末50平均reward | 無風跑滿 | 弱風跑滿 | 實際有風跑滿 |
|---|---:|---:|---:|---:|---:|---:|
| 來源1600 | — | — | — | 19/20 | 19/20 | 16/16 |
| 基準1700 | 236074 | 1839.35 | 1938.02 | 6/20 | 5/20 | 3/16 |
| 半速1700 | 249328 | 1953.66 | 1741.68 | 3/20 | 4/20 | 4/16 |

基準 run：`20261116_174713_recovery_tp4d3827cd`。半速 run：`20261117_001300_recovery_tp0c3b83f1`。兩臂是從1600另建的不同分支，不是同一run先後兩段。

三份 evaluation 各40次，均complete、關探索、weights_unchanged、最多3000步。重新由120筆逐次結果計算彙總，核對環境／課程／runtime／random-path hash一致、stage/seed唯一且風參數配對。20個seed各兩風況，不是40條完全獨立路線。

| 模型 | 舊集 無風／弱風（各10） | 新集 無風／弱風（各10） |
|---|---|---|
| 來源1600 | 10、10 | 9、9 |
| 基準1700 | 3、3 | 3、2 |
| 半速1700 | 3、2 | 0、2 |

舊seed 2000011501–1510，新seed 2000011601–1610。弱風實際有風分別9及7條。全部提早終止皆有 distance_threshold 證據，來源2次、基準29次、半速33次；這是終端觀測證據，不擴張成已追蹤完整 IsDone 實體分支。

來源後10秒原有限路線距離：全軌跡最大兩風況皆51.01m（含失敗），只看跑滿軌跡最大41.34/45.83m。逐軌跡RMS平均9.27/9.41m，因失敗軌跡時長不同，不當成同時長精度優劣。來源仍不是全面高精度或原frozen gate已通過。

## 決策

兩臂均未保留來源跑滿能力，沒有推薦直接延長的勝者。半速全段訓練reward較高、凍結跑滿較少，但凍結平均步數略高，不能說所有指標均較差。每配方只有一個訓練trial，等episode不等step，平行軌跡與更新量不保證相同，尚不足推論LR普遍因果優劣。

保持兩個1700及舊2100 paused、保留1600，不跳Stage3、不開continuous、不再直接執行ActorPilot訓練。下一個遠端入口為 `-PilotProbe`：從已完成pilot核對來源，複製已評估模型到隔離目錄，對每臂1600/1700做已保存狀態、相同replay輸入及雙Q動作曲線診斷，完成自動ZIP。它不會訓練、sim或開pool，不再多跑120次飛行。

這是一次補齊兩臂機制證據的操作，不保證能定位根因。若仍只有「策略改變／Q改變」而無可區分的假設，應暫停LR掃描，在meeting討論任務與reward/觀測設計；不得自動從診斷升級為新訓練。若後續有具體假設，再從1600另建短分支，預先定義單一變因與能力保留驗收，不從退步1700續跑。指令見 [接續指南](../guides/sac-actor-pilot-next-2026-11-17.md)。

## Meeting 20261119

`output/meeting_sac_20261119/dist/SAC_Meeting_20261119.pptx`，22頁、7個原生圖表與內嵌工作表、10個原生表格，逐頁中文講者備註及來源。沿用個人Fixed-Wing UAV Lab模板，資料截至11/17，沒有index.html演示。涵蓋論文差異、隨機路線主線、先前弱風回溯、自動cycle、新child回溯、內部probe、最新兩臂短對照及討論。

結構、字型、表格／圖表資料與first-party import檢查通過，layout finding=0。以原生PowerPoint唯讀匯出全部22頁，逐頁檢視：無預設座標軸標題重疊，圖表／中文均正常。未操作Edit Data視窗，不宣稱Google Slides驗證。圖表移動平均為顯示而四捨五入4位小數以符合Excel數值精度；原始資料不改。

PPT SHA256 `062f81788f8e7ffe5666cf5ffc8032517d42426716200de44e87bf949c633aeb`。來源模板與舊簡報未更動；PPT、ZIP、模型、完整日誌不加入Git。

## 新入口驗證

R2024b隔離fixture使用封存來源1600及本批兩個1700真實模型，完成兩臂的保存狀態、共享replay輸入與16×33×雙Q CPU推論，來源／權重未變。fixture的1600採未改LR的原始來源，recovery文件為測試配置，不冒稱已驗證遠端兩份prepared1600的optimizer保存。將fixture評估SHA改錯後，腳本以 `PilotProbe:Changed` 拒絕，未進入錯誤模型推論。測試無train、sim或pool。

Windows PowerShell5.1 `-PilotProbe -PackageOnly` 隔離打包與payload SHA核驗通過，Parser及git diff --check通過。遠端完整實跑尚待使用者執行；本機測試輸出只作工具驗證，不自動改寫為正式遠端diagnosis或新的訓練結論。
