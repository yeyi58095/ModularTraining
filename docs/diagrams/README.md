# 訓練流程與程式原文

開啟 `training-explorer.html`。單檔可離線使用，原始碼與主圖皆內嵌，不需要 MATLAB 或服務程序。

- 點選方塊或上方步驟選單，開啟程式碼側欄。
- 在圖表空白處按住滑鼠拖曳，可在 100% 下平移，把側欄遮住的右側方塊移到左側；「重設圖表位置」回到完整圖。
- 側欄左邊緣調寬度，下邊緣調高度，左下角同時調整兩者；左／下邊緣聚焦後也可用方向鍵調整。
- 長程式碼可開「拖曳閱讀」後直接拖動，或開「自動換行」。關閉拖曳閱讀後恢復一般文字選取。
- 側欄顯示責任、關鍵分支及相關區段；點選區段切換原文。
- 「顯示完整檔案」保留行號並標出對應區段；「展開閱讀」提供較大的閱讀空間。
- 搜尋涵蓋說明、檔名與映射區段的程式原文。
- 網址的 `#prepare`、`#saved` 等可直接開啟指定步驟。
- 「課程 JSON 範例」顯示 `experiments/progressive_v1/curriculum.json` 原文、欄位說明與六階段分頁。範例不代表任何 run 的實際進度，也不會套用設定或修改 JSON。
- 圖表內建縮放、搜尋、匯出等操作介面採用英文；流程內容與程式碼面板採用繁體中文。

本圖是 2026-10-12 目前專案原始碼的概覽，涵蓋 `retry.m`、supervisor、attempt、training engine、課程與 guard。主圖省略部分提前返回與例外箭頭；它們在對應方塊的說明及原文中明列。未展開 Simulink 模型內部或 MATLAB `train` 內部演算法。這不是實際訓練執行追蹤，也不代表歷史 run 使用相同程式版本。

原文是建置時快照，不會自動跟隨工作區修改。每個來源帶 SHA-256，完整清單在 [evidence/training-explorer.sources.json](evidence/training-explorer.sources.json)。本工具只讀取列出的程式檔，不讀 checkpoint、實驗日誌或 MAT，不啟動訓練，不修改 runtime 或 run。

## 更新

主圖規格在 `src/training-flow.workflow.json`，經 Archify `validate` 與 `deliver` 產生 `assets/training-flow.html`。保持此已驗證產物原樣，程式碼探索器另行內嵌它。HTML 模板及建置／檢查工具放在 `src/`，收據與截圖放在 `evidence/`。

在專案根目錄執行：

```powershell
node docs/diagrams/src/build-training-explorer.cjs
```

建置程式中的 `span` 定義維護方塊到程式區段的映射。2026-10-12 補註解後已重映射行號，快照包含中文註解與課程 JSON 原文。程式異動後需重新審查映射的語意與行號；建置只檢查範圍有效，不會自動推斷控制流程。

`evidence/training-flow.delivery.json` 是主圖的 9/9 showcase 檢查與 SHA-256 紀錄；`evidence/training-flow.visual-check.json` 是主圖四種桌面尺寸的瀏覽器證據。`evidence/training-explorer.check.json` 紀錄探索器互動與原文對應檢查。[驗證說明](evidence/verification.md)；自動檢查不取代實際截圖的視覺審查。

`src/check-training-explorer.cjs` 是驗證輔助程式，從 Node 執行檔位置尋找 bundled Playwright，從 ProgramFiles 尋找 Chrome；它不是訓練依賴。其他工具環境可能需要調整尋找方式，HTML 成品沒有這些依賴。
