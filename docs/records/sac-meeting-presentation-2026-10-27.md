# SAC meeting 簡報 — 2026-10-27

使用者確認使用個人 Fixed-Wing UAV Lab Paper Review 模板，要求將目前工作總結為meeting報告。已完成 `output/meeting_sac_20261027/dist/SAC_Meeting_20261027.pptx`，24頁（主報告含封面20頁、附錄4頁），246,622 bytes，SHA256 `d0ebb09ae611acd54f777460b772b269717986ca50ce0e9c3286d64e49df440d`。

模板來源為個人skill保留的 `assets/reference.pptx`，原檔SHA256 `e6792c375b50956b71235665b8831805fc0c408132005ae2387e17124b2d8416`。原模板35頁已全部render／讀取內容；選用原封面與文字頁的layout／master，沿用4:3、960×720、藍色框線與頁碼，以及Times New Roman／標楷體。未修改模板或使用者原有meeting簡報。

## 報告安排

1. 封面及研究現況：PPO已完成39300回合但保留Stage8特定情境偏離限制，SAC為獨立新agent。
2. 共同環境／評估語義與實驗時序。
3. SAC+LSTM平行及serial CPU訓練、凍結checkpoint，說明訓練曲線與保存模型不同。
4. replay100k／500k、LSTM actor LR調整，分開說明目的、結果與不能下的因果結論。
5. MLP實務對照、完整1–2500歷程、2100／2300／2500凍結結果。
6. MLP低actor、共用輸入策略／動作Q、慢critic及2200／2500凍結結果。
7. 目前結論、供meeting討論的後續方向。
8. 附錄列起始SAC參數、LSTM與MLP分支來源、指標定義與證據限制。

每頁備註有中文講解與來源路徑，未保留模板原論文內容作為本專案實驗證據。完整run ID在分支頁備註，畫面使用可讀的分支名。既有日誌／JSON與前次來源核對紀錄供數據，不啟動新sim或訓練。

## 可編輯內容與驗證

- Artifact Session中建立及修改24頁，保留模板的master／layout結構；session artifactRef為 `artifact_yYHc_GxDtTSZ55uG5p6wFkH-5jMCHieb`。完整模板含原論文影像超過session單次更新上限，改只導入會使用的封面／文字頁及其原layout／master，不帶入無關原論文影像。
- 匯出檔有20個native charts、12個native tables、24份講者備註；20個圖表各有內嵌XLSX新數值快照，支援後續改圖表資料。這些workbook由本次完整literal圖表資料新建，不冒稱保留原始Excel公式或工作簿lineage。
- 訓練曲線採完整連續100回合均值，每10回合顯示一點並保留末點；祖先按來源checkpoint裁切。native圖表數值保留6位小數，避免Excel有效位數限制；原始日誌／JSON不改。圖表標籤另依用途顯示整數或2–3位小數。
- 來源raw資料保留在既有intake；原26張完整圖片仍在 `artifacts/meeting/sac_charts_20261027_complete/`，簡報以摘要所需的native圖表重建，不將全部原截圖當作一整頁平面圖片。
- 套件完整性pass、版面／字型檢查0 finding、native chart資料與內嵌workbook核對pass、first-party重新import成功。字型檢查實際觀察到的文字只使用Times New Roman與標楷體。
- 24頁皆從最終PPTX重新render；逐頁目視檢查，修正擁擠的滿長率圖例、邊界座標標籤、N/A單位及孤立標點。參照模板封面／文字頁比對藍色框線、字體與4:3版面。
- 最終檔SHA、20 workbook／20 chart、24備註皆重新核對，模板SHA不變。私有驗證紀錄在 `output/meeting_sac_20261027/build/validation_meeting.json`，逐頁預覽在 `build/final-render/`，總覽在 `build/meeting-overview.jpg`。
- 沒有在原生PowerPoint UI開啟或手動編輯測試，不宣稱已驗證使用者Office版本的實際字型／Chart Edit Data視窗行為。已完成的是檔案結構、數值、匯入與render驗證。

所有來源、既有run、checkpoint、環境／課程快照保持原位；沒有遠端連線、啟停訓練或更動runtime。後續實驗頁屬供meeting討論的建議，不視為新訓練／改門檻授權。簡報與本機建置資料不加入Git；此記錄與入口可同步。
