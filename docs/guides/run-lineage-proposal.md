# Run 繼承關係與跨 run reward 畫圖

2026-10-10 記錄構想；2026-10-11 使用者授權實作畫圖工具與文件。實作僅在 `tools/plot_training_rewards.py`，訓練端與既有 run 資料維持原狀。

## 使用方法

原本指令即可自動包含父 run，不需要修改實驗 JSON：

```powershell
python tools/plot_training_rewards.py "experiments/progressive_v1/runs/C" --watch 60
```

輸出預設仍在 C 的 `reports/reward_history.png` 和 `.csv`，祖先 run 不會收到輸出。停止並重啟 Python 畫圖程序即可載入新版本；訓練中只更新畫圖檔，不需重啟 MATLAB 或更新 runtime。

只看目前 run 的原始日誌：

```powershell
python tools/plot_training_rewards.py "experiments/progressive_v1/runs/C" --no-lineage
```

父 run 的跨機絕對路徑已失效時，可提供目前存放父 run 的專案根目錄、課程資料夾或 `runs/`，此選項可重複：

```powershell
python tools/plot_training_rewards.py "experiments/progressive_v1/runs/C" --lineage-root "D:/archive/ModularTraining"
```

工具優先使用記錄中的有效路徑；相對位置依子 run／搜尋根目錄解析。失效路徑使用末段 run ID，在同層 runs、本專案及額外搜尋根目錄的標準 experiments、模型 runs、舊 sessions 結構尋找。候選須唯一，不會依時間或名稱相似度猜測。若多份同 ID 副本造成歧義，請使用原記錄路徑可解析的資料配置；`--lineage-root` 增加搜尋位置，不會覆蓋有效路徑或自動消除歧義。工具不掃描 Flower 或任意遞迴目錄。

## 曲線語意

例如 A 跑到 12600，B 從 A 的 10600 接續；B 跑到 11600，C 從 B 的 11000 接續。畫 C 的來源路線為：

| 來源 | 採用 episode |
| --- | --- |
| A | 1–10600 |
| B | 10601–11000 |
| C | 11001 起 |

A 在 10600 後、B 在 11000 後的其他分支資料不會接入 C。若中間 run 沒新增回合、直接再次分支，其空區段不重複計入祖先資料。同 run 重複 episode 仍使用較新 attempt；不同 run 不互相覆蓋。只有日誌內完整行才納入，寫入中的最後一行等待下一次 watch 更新。

- 淡藍色：每回合 reward。各 run 平均 reward 分色；圖例標示來源 run。
- 紫色虛線：繼承 checkpoint 與子 run 的接續點，位於 N 與 N+1 之間。
- 灰色虛線：同 run 內 attempt 分界。
- 橘色線與軸下文字：各 run 保存的 curriculum stage 歷史；繼承的相同階段不重複標示，不把接續點當成換階段。
- 缺少 episode 的區域留斷線及灰色底；缺少祖先時仍畫已知子 run，並在圖上與 console 提示。找不到中間祖先時，不能推測更前面的歷史。

CSV 保留 reward、average_reward、steps、total_steps、q0、attempt，新增 `source_run` 與 `source_session`。後者是目前讀取的完整本機路徑；CSV 與 PNG 沿用 Git 忽略規則。

## 判讀與驗證限制

平均 reward 直接使用各 run 日誌值，不跨分支重新平滑。圖例的 `configured avg window` 讀取目前 control.json，不能證明歷史所有 attempt 的窗口相同；未知值標為 unknown。圖例 `prep SLX` 為 recovery.json 內 prepare 時的模型指紋縮寫，不代表歷史實際執行版本。actor LR 亦為 recovery 準備時記錄。沒有準備紀錄的原始 run 標示未知環境；reward 定義與歷史環境未被此工具核驗，同圖不代表分數可直接比較。

工具偵測循環引用、無效 episode、已知 AgentN／CandidateN 檔名與 episode 不符，以及父 checkpoint 早於該父 run 自身繼承起點。遇到錯誤停止追溯、發出警告；不修復 JSON、編造記錄或連接缺漏曲線。不載入 MAT，不核驗 checkpoint SHA256 或權重；它呈現 metadata 記錄的來源路線，不能作續訓完整性驗證。既有 `trainingtools.verify_training_session`／audit 工具用途不變。

來源讀取為唯讀，不搬移 run、不改寫 checkpoint、curriculum、control、guard、stage state 或日誌，不控制訓練。watch 每次重新讀取來源鏈與日誌，較長祖先會增加 I/O；若需要降低更新負擔，可增大 watch 秒數。只讀檔案不會改變模型學習條件。

`tests/test_plot_lineage.py` 與既有 `tests/test_plot_stages.py` 使用合成日誌驗證三代截斷、不重複繼承歷史、同 run attempt 覆蓋、半行忽略、跨機路徑、歧義、缺失父 run、錯誤 episode／checkpoint、循環、stage 分界、PNG／CSV 與來源檔案不變。這些測試不啟動 MATLAB，不代表實驗室的完整祖先日誌已在本機驗證。

## 尚未實作

所有分支的並排比較、steps／其他指標圖、專用可跨機 lineage schema、歷史執行環境／reward 定義的完整版本證明。現有功能使用既有 recovery.json，不新增或改寫 run 來源 metadata。
