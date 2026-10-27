# SAC meeting chart collection — 2026-10-27

使用者本次要求先整理 SAC+LSTM 與純 SAC 圖片、確認可完整畫圖，供日後依「起始訓練 → 問題 → 嘗試調整 → 調整後結果」製作 meeting PPT。本次沒有製作或修改 PPT。

交付資料夾：`artifacts/meeting/sac_charts_20261027/`。共 16 張重畫 PNG、1 張收到的原始截圖、1 張 JPG 總覽；附 `index.html`、中文 `README.md`、來源 `manifest.json`。PNG 全部集中於同一層。01–16 依實驗／診斷先後編號，17 為原截圖附錄。資料不隨 Git 同步。

重建入口：`tools/build_sac_meeting_charts.py`，從自身位置推導 project root，資料來源唯讀；預設輸出已存在會拒絕覆寫。需要 matplotlib、numpy、Pillow；本機套件放於 Git 忽略的 `artifacts/plot-python-deps/`。可指定全新輸出資料夾重建：

```powershell
python .\tools\build_sac_meeting_charts.py --output .\artifacts\meeting\sac_charts_new_batch
```

本機實際以 bundled Python 執行成功（系統 python 是 WindowsApps alias），不是宣稱上方 `python` alias 已可執行。

## 圖表內容與完整性

| 圖 | 來源與範圍 | 處理／限制 |
| --- | --- | --- |
| 01 | 舊 GPU 設定／6-worker SAC+LSTM，1–2150 | 使用既有 diagnostic ZIP 較新的三段 stdout；不以早期 2144 日誌截斷，不宣稱該組最終回合 |
| 02–03 | 新 serial CPU SAC+LSTM，1–2000 與四個 checkpoint 評估 | CSV 1–1905 與 attempt4 合併，重疊逐回合核對一致，535 筆包含 echo 的日誌去重為 500 個 episode |
| 04–05 | 100k／500k replay 子run，從同1100至1600，配對凍結評估 | 祖先只裁切至1100；不同分支互動步數不等，不宣稱等計算量因果改善 |
| 06 | 五個LSTM checkpoint，同兩段歷史序列 | Gaussian mean/std 及歷史動作雙Q；灰色前64輸入，不是飛行／TD誤差 |
| 07–08 | 1600來源的兩組actor LR，至2100及有無探索評估 | 祖先裁切至1600，避免接入父run後續資料 |
| 09–10 | MLP新agent 1–1000；連續child已收2001–2500 | **1001–2000缺完整逐回合資料**，灰色留白；不能稱全歷程已完整 |
| 11 | 原MLP 2100／2300／2500，seed101關探索 | 分開呈現步數、reward及10秒後有限原路線最大偏差 |
| 12–13 | MLP降低actor LR，2101–2500及2500關探索 | 訓練對照含原2001–2100；凍結來源2100與child2500分組 |
| 14–15 | MLP三快照共用歷史輸入及16×33動作Q網格 | Q每觀測減去該網格最大值以顯示偏好，非Q正確／高估／根因證明 |
| 16 | 低actor／慢critic，各2101–2500共400回合 | 慢critic **2200／2500凍結評估尚未收件**，未繪製不存在的評估 |
| 17 | 已收buffer500k截圖 | 複製後SHA256一致，保留原樣 |

全部訓練圖含原始逐回合reward／steps與完整100個連續回合移動平均／跑滿率；移動平均不跨缺口。凍結評估獨立成圖，bars為平均、dots為各次結果，使用原JSON的10秒後路線距離；不足10秒標示N/A，不混用初始50m。訓練跑滿與凍結表現不同，固定路線多seed不代表多條路線。MLP與LSTM同時改架構／sequence length，圖不是單因素因果證據。

未收到完整歷史loss／TD-error時序，不宣稱可從checkpoint恢復此類曲線。MAT完整軌跡未納入此批重畫；評估圖使用evaluation.json摘要。

## 驗證

- 實際批次執行完成：17 PNG、38個來源檔，來源前後SHA256不變，manifest逐圖列出來源與圖片SHA。
- 每張PNG以Pillow重新開啟verify；原截圖複製後SHA與來源相同。
- 已開啟整批總覽目視檢查：標題、軸、圖例、分支邊界、缺口與附註可見；評估圖預留旋轉標籤空間。
- 來源重複episode不重算；不同內容的同episode會報錯；來源CSV run ID明確核對。
- `git diff --check`通過；未修改runtime、來源檔、既有run、模型或使用者簡報，未啟停訓練，未連線遠端。

下一步若要補全MLP逐回合曲線，只需由使用者提供遠端 `20261026_203618_recovery_tp18ecff57` 的 attempt_00001／attempt_00002 stdout（1001–2000），或保留source_run的完整reward CSV。目前不為補圖啟動任何訓練或重跑評估。
