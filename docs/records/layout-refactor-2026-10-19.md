# 根目錄縮編與第三組開訓前準備

使用者要求完成目錄重構，之後由使用者 push，再開始第三組從頭訓練。本次先完成程式與本機資料整理；不替使用者 push，不連線操作實驗室，不建立或啟動第三組正式 run。

## 變更

- 根目錄移出 19 個工具檔：10 個 Python／PowerShell 到 tools/，9 個 MATLAB 準備／稽核工具到 +trainingtools/。根目錄保留 retry、training、training_status、curriculum_plan、resolve_curriculum_path、compare_training_checkpoints。
- 改正工具自身位置推導 root、Python 模組匯入、精簡報告的程式指紋清單、PowerShell 輸出指令、MATLAB 套件呼叫、操作文件與測試。Windows PowerShell 工具使用 UTF-8 BOM，避免中文路徑在 Windows PowerShell 5.1 下被錯解。
- 既有 run、環境、課程、模型 profile、runtime、guard 邏輯及歷史診斷資料不因分類而搬移或修改。舊根目錄同名工具不保留轉接檔；歷史指令依 tools/README.md 換入口。歷史流程圖與證據維持原快照，不冒稱已跟隨本次程式更新。
- 新增 compact_workspace.ps1：預覽後才能 Apply，拒絕既有目的地、tracked 來源與連結；在移動前檢查絕對路徑仍在 workspace，移動前後逐檔 SHA256。不中斷式自動復原，若中斷依 receipt 查核，不能強制重跑覆寫。
- 本機 .meeting-build 與根 Python 快取共 118 檔已整理；receipt 為 artifacts/incoming/layout-20261019-124841-4030dddc/manifest.json。12 份建置腳本另更新相對位置，原稿完整保存於 original-scripts，修改前後 SHA 在 script-path-updates.json。未重建簡報；已有機器專用套件路徑仍須在未來重建前核對。
- 原有已修改 PPTX 與未追蹤 ZIP 保留原位，不納入提交。模型、完整日誌、測試輸出、依賴及整理後 build 仍被 Git 忽略。

## 驗證與限制

- 修改前 Get-Process 未發現 MATLAB 程序。CIM 查詢因權限受限，沒有將失敗查詢當成遠端或本機活動狀態證據。
- 42 項既有 Python 測試通過；新增工具位置測試 1 項通過，涵蓋從外部工作目錄執行三個 CLI 的 --help、成果與報告根目錄定位。測試依賴放 tests/output/layout-deps，未修改全域 Python；TEMP／TMP 改用 tests/output 以避開 sandbox 暫存權限問題。
- PowerShell：diagnostic_package、organize_reports、preserve_environment、migration、compact_workspace 五組通過。compact 驗證預覽不搬、原始簡報位元組、腳本備份與更新、快取封存、重跑與目的地衝突。工具全部通過語法解析；實際 organize_workspace 回報 Nothing to organize，compact 重跑回報 Nothing to compact。
- MATLAB 六組通過：tool_layout、progress_recipe、recovery_guard、training_std_scale、continuous_training、resume_audit。從專案外呼叫套件／第三組 preflight 成功，progressive_v2 課程 SHA 與 runs 名單不變；恢復與稽核測試來源雜湊保持。
- **training_std_scale 包含 2 回合 × 512 步的合成 CPU PPO 更新**（rlFunctionEnv，非飛行環境）；不能寫成所有測試均無 train。其餘本批 MATLAB 測試為準備、唯讀稽核或假引擎。曾在進度訊息中誤稱全批無 train，後已更正。沒有正式飛行訓練、GPU／多 worker 或長期收斂驗證。
- 原文件整體驗證器保留當時固定 22 份文件的驗收條件，不能直接當現在文件數的檢查。歷史圖表／JSON 不改寫以迎合檢查；本次改以新入口與本機 Markdown 連結核對及重建離線索引驗證。
- 本機日誌：tests/output/layout-python.log、layout-powershell.log、layout-matlab.log。這些與 fixture 不加入 Git。
- 完成超過 120 個本機 Markdown 連結檢查、118 個搬移後檔案及 12 份原稿雜湊核對、Python／PowerShell 語法檢查、git diff --check；離線文件首頁重建為 49 份文件並通過內嵌 JavaScript 語法與新增入口檢查。未宣稱重做整套瀏覽器視覺驗收。

## 第三組邊界

新增 trainingtools.preflight_round3：唯讀核對現有設定 start=false、無 resume、ppo_lstm128、八階段、spatial_v2 資產 SHA，回傳課程 SHA 和設定，不建立 run／agent／pool。輸入準備仍用 prepare_progressive_v2_training；只補缺少資產，既有不同內容拒絕覆寫。

本機 preflight 通過，環境 SHA 為 997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557，當次課程 SHA 為 6dc1ee14695c3e210a4f1e215a56df0890fc0f8d10bc61bda52fc676c9acf3e6（檔案位元組雜湊，跨機換行差異需另核對）。第三組沿用 progressive_v2 名稱，從新 agent 開始，各階段沿用同一 agent；不接續 39300／18500，不自動套用恢復分支的 LR／探索倍率或 continuous 模式。尚未建立第三組正式 run 或驗證從頭收斂。

下一步見 [第三組準備](../guides/round3-fresh-training.md)：使用者 push、本機與實驗室同步確認後，再建立並核對新 run，最後另行啟動。
