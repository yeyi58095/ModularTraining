# 原始碼註解與課程範例（2026-10-12）

對 79 個 Git 管理的專案／測試程式補上 383 行繁體中文註解：61 個 `.m`、10 個 `.ps1`、8 個 `.py`。保留既有英文註解，新增檔案用途、輸入輸出／副作用、函式責任、關鍵分支與限制；不為每個直觀賦值重述語法。

範圍包含入口、runtime、模型定義、課程、guard、checkpoint 評估、遷移／報告／診斷打包及 Python 畫圖／匯出工具與測試。未修改 `runs/`、`tests/output/` 既有測試產物、`diagnostic_packages/` 內的歷史來源副本。驗證輔助產物新寫在忽略的 `tests/output/`，不作訓練輸入。

修改前以唯讀程序清單確認本機沒有 MATLAB 訓練程序。本次沒有啟動 train、sim、pool，也沒有更改 SLX、checkpoint、control、guard 或任何課程 JSON，未 commit／push。

## 驗證

- 逐檔刪除本次新增註解後，79 個檔案原始 bytes 還原一致。
- 10 個 PowerShell 檔案 parse 成功，排除註解後的 executable tokens 與 AST 節點結構一致；沒有執行這些腳本。
- 61 個 MATLAB 檔案只執行 Code Analyzer，診斷種類／內容一致。既有 ALIGN 訊息內的 END 行號因註解平移，比較時只正規化訊息中的 `on line N.`。
- 8 個 Python 檔案的 AST（忽略位置資訊）一致；不執行原工具／測試。
- 訓練與評估的 fixed／random 路徑函式同步補同一份註解，原有逐字一致性檢查仍成立。
- `git diff --check` 通過。

補註解仍會改變程式檔的 SHA-256，因此新的 engine／工具指紋不可直接當成演算法或模型環境變更；本次可執行內容保持不變，SLX 原件也沒有修改。既有 run 及報告所記錄的歷史指紋沒有重寫。

## HTML

`docs/diagrams/training-explorer.html` 已更新原文、來源 SHA 與對應行號。它仍有 12 個流程方塊，另外增加「課程 JSON 範例」入口：完整 progressive_v1 JSON 與六階段分頁，旁邊解釋 `model`、軌跡／風場、all 條件、連續視窗與階段預算。JSON 保持標準格式，沒有往設定內加註解或新 schema 欄位。

範例是共享定義的快照，不代表 run 階段、不內嵌 MAT、不啟動或套用課程。瀏覽器檢查包含 19 份內嵌來源與工作區一致、全部程式區段、六階段 JSON、點選／搜尋／連結以及四種桌面尺寸，詳見 [圖表驗證](../diagrams/evidence/verification.md) 與 receipt。

## 後續加強

使用者確認正式訓練只在遠端，本機沒有活動訓練。此次只修改本機副本，未連線或更新遠端 runtime。

另在 10 個 `.ps1` 與 10 個核心 `.m` 檔加入 298 行註解，累計本次對話新增 681 行。PowerShell 說明包含 `$變數`／型別轉換、`param` 與必填參數、陣列與 hashtable、管線與 `$_`、dot sourcing、作用域、比較／位元運算、正規表示式、.NET 靜態方法／物件方法、程序引數及續行、錯誤／資源清理。相關说明放在實際操作旁，原有可執行行保持原樣。

新增註解的原始 bytes 還原檢查及 PowerShell token／AST 比較通過；61 個 MATLAB 檔 Code Analyzer 診斷保持一致，路徑函式的逐字相容檢查通過。檢查時抓到並修正一處註解插在 `...` 續行 options 內的語法問題，現已移到整段呼叫之前；沒有改 executable code。
