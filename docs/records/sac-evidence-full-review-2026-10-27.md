# SAC完整收件、補圖與慢critic凍結結果 — 2026-10-27

本次使用者將 `sac-evidence-20261027-124013-c1438015.zip` 放於本機專案根目錄。已核對ZIP SHA256 `61172eff189ad6c83281f0f6f223fb1427e30b0942a4a0e048161e4b39895b1b`、44,781,961 bytes，逐一解壓並核對809個納入檔案的bytes及SHA，全部一致。

封包已歸檔至 `artifacts/incoming/sac-evidence-20261027-124013/`，根目錄原路徑／目的地／SHA／遠端來源路徑記於 `intake-manifest.json`，搬後再次核SHA。原封包不改；未處理其他未知ZIP或使用者簡報。

直接重建完整路徑會超過Windows MAX_PATH，因此正式解包使用 `files/0000.ext` 等短檔名；`extraction-index.json`逐一保留ZIP內完整原專案相對路徑、local_file、SHA與bytes，`source-manifest.json`保留原manifest與遠端絕對路徑。最初失敗的生成暫存副本已移除；原ZIP／來源均保留。這個本機分析索引不是可續訓run。

## 9個issues與排除清單

9個issues**全部為 `generated_cache_directory_skipped`**，對應各run的 `environment/slprj`；無遺失父run、無效JSON或來源變動警告。809個納入檔案的 `changed_during_copy` 全為false，但它仍是逐檔非原子快照，不當遠端即時狀態或完整備份。

228個排除項為207個未選取MAT、11個鎖檔、9個產生二進位／dump、1個既有封包。評估trace依使用者選項有納入；訓練checkpoint／replay不在本包，因此不能宣稱本機重新載入模型核驗或可直接retry。

12個資料夾包含10組有attempt紀錄的SAC訓練run、1個零attempt的prepared舊分支、1個零attempt的失敗`.preparing`。後兩者不當作已訓練模型。10組run的18個主要attempt均有stdout；diagnostics下副本未重算。

| Run／分支 | 本run回合範圍 | attempt數 | 本run互動步數 |
| --- | --- | ---: | ---: |
| 20261020_201931 舊parallel LSTM | 1–3000 | 3 | 2,949,865 |
| 20261021_200746 serial LSTM | 1–2000 | 4 | 1,823,231 |
| 20261023_203402 replay100k | 1101–1600 | 1 | 750,422 |
| 20261023_204044 replay500k | 1101–1600 | 1 | 1,053,075 |
| 20261025_235136 原actor LR | 1601–2100 | 1 | 520,648 |
| 20261025_235817 低actor LR | 1601–2100 | 1 | 646,929 |
| 20261026_184028 MLP從頭 | 1–1000 | 2 | 182,371 |
| 20261026_203618 MLP連續child | 1001–2500 | 3 | 1,764,063 |
| 20261027_015231 MLP低actor | 2101–2500 | 1 | 290,091 |
| 20261027_095822 MLP慢critic | 2101–2500 | 1 | 414,603 |

先前缺的MLP1001–2000已補齊，child完整lineage現為1–2500。舊parallel組從先前2150補至3000，封包狀態為paused／maximum attempts，並非新啟動或現在即時監控。每條lineage依 `parent_episode`裁切祖先，10條有訓練的完整lineage皆為連續回合；只表示本包已識別run資料齊全，不等於所有可能存在的外部實驗均被發現。

## 新收到慢critic凍結評估

兩報告皆complete、weights_unchanged=true、Stage1／seed101／探索off／max3000。環境spatial_v2、SLX SHA `997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557`、課程SHA `0cb7430587f8c548e5a97edf95149e702caeefb337f7fc47978170b62989389f`一致；兩新報告runtime SHA均 `f01b62ab1d9398e04d3ee668f99d2f334d8dc5b6f144922791bbe3edff68eda2`。早先原MLP2100評估runtime SHA為另一版本，故圖上的來源比較不冒稱完全相同執行版本的因果對照。完整hash保留原JSON，weights不變為評估器回報，未本機重sim。

| Checkpoint | Reward | Steps | 10秒後原有限路線最大偏差 |
| --- | ---: | ---: | ---: |
| critic慢速2200 | 2734.76 | 3000 | 6.182 m |
| critic慢速2500 | 96.08 | 163 | 50.359 m |

2200保有本次單seed跑滿能力，但2500關探索仍失敗，與訓練退步方向一致；沒有證明慢critic修復退步或全面穩健。原參考2100後段偏差3.488m，不能只看滿長率說調整後較好。保留既有paused，不繼續盲降LR、不啟動新訓練。

## 圖片交付與驗證

新版統一資料夾：`artifacts/meeting/sac_charts_20261027_complete/`。

- 01–18：依實驗／診斷時序重畫PNG，含訓練reward／steps／滿長率、全部18份既有evaluation.json、共用輸入診斷與動作Q。
- 19–26：本次收到的8張原PNG截圖附錄，逐一複製核SHA；原截圖可能較早生成，例如舊parallel圖只至2150、serial圖只至1910，以重畫圖為完整收到日誌依據。
- `00_contact_sheet.jpg`、`index.html`、中文README與逐圖來源manifest；原初版資料夾保持原位，新版供後續meeting使用。
- 26 PNG全部重新開檔verify；102個用於出圖的來源前後SHA一致；總覽及11、18主圖目視檢查通過；18／18主要attempt、18／18評估JSON覆蓋斷言通過。
- `tools/build_sac_collected_charts.py`提供可重建入口，使用同資料夾唯一ZIP時可重建短路徑索引。依賴與原builder相同；實際使用bundled Python成功出圖。

```powershell
python .\tools\build_sac_collected_charts.py .\artifacts\incoming\sac-evidence-20261027-124013 --output .\artifacts\meeting\sac_charts_another_batch
```

此指令需可用Python與既有繪圖套件，系統WindowsApps alias不當作已驗證入口。未啟動MATLAB、train或新評估，未修改runtime／既有run／來源封包；未製作PPT。沒有歷史連續loss／TD-error資料，不補造。圖片／封包僅本機保存，不因工具與紀錄commit/push而自動同步到另一台。
