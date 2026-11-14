# 半速 SAC 自動評估與有界續訓：實作驗證

11/14 使用者要求遠端腳本先比較不同 episode、依規則選可續訓分支、自動訓練並交回兩階段結果，後續補充允許符合條件時升stage。固定範圍為現有半速來源1500–2000，不擴展舊SAC/PPO實驗。規則與執行見[操作文件](../guides/sac-review-cycle-2026-11-14.md)。

## 實作

- `run_sac_review_cycle.m`：120次候選凍結飛行、另批路線複核、SHA綁定來源，先寫準備／啟動意圖，再建立唯一子run與限一次attempt的supervisor。中斷後不自動重複啟動。
- `select_sac_review.m`：完整stage/seed配對、兩風況80%門檻、實際有風子集、相對1500保持能力，依較弱階段表現排序；複核失敗不反覆選第二名。
- `prepare_recovery_training.m`只新增`reviewedWind`特定配方路徑，允許同一已完成2000來源的1500–2000 checkpoint。位元組複製，不重建optimizer／replay，不改父快照；原extend路徑仍要求選定episode等於來源停止回合。
- 升階不改runtime／curriculum邏輯。達原訓練條件後，用原frozen gate的seeds／距離條件測Agent_Final，再讓既有prepare轉stage。同一子run總預算500不重設；最多四次supervisor啟動，錯誤／paused guard不自動解鎖。
- PowerShell wrapper與窄範圍packager：正常或MATLAB錯誤退出都嘗試打包，只收本cycle與該child；子run若仍有鎖則明示未收。包含RESULTS.md、選擇／複核、訓練窗口、升階、最終固定策略評估、日誌與模型。逐檔讀回驗SHA。

## 已完成驗證

- R2024b `test_sac_review_cycle`：隔離假評估器／假supervisor，驗證選出1700、複核、原gate通過後Stage2→3、累計500上限；另驗證無候選、複核失敗、gate失敗後不升階、已完成重跑不開新attempt、重複seed拒絕、無實際風樣本拒絕、交件損毀拒絕、既有launch intent拒絕重啟。假supervisor只啟動立即退出的cmd程序，不呼叫訓練。
- R2024b `test_sac_review_preparation`：用封存真實半速Agent1500，在獨立合成2000停止狀態下建立測試子run；來源／子checkpoint SHA一致、原檔不變、stage2/start1000、500預算、maxAttempts1、STOP保留、沒有attempt；錯誤SHA拒絕。產物在`experiments/sac_review_preparation_fixture`，不是正式實驗結果。
- 舊`test_sac_wind_history_batch`回歸通過，六checkpoint假批次／核對略過／損毀拒絕正常。
- Windows PowerShell5.1 `test_pack_sac_review_cycle`：正常ZIP內容只屬cycle/child、含最終模型與選擇結果；逐檔SHA驗證；持有child lock時只收cycle且註記缺項；PackageOnly不啟動MATLAB。
- MATLAB Code Analyzer沒有語法錯誤；僅清理提示與單行else排版提示。PowerShell parser與git diff --check核對。

本機普通sandbox啟動MATLAB曾因偏好資料夾不可寫與授權服務5202而失敗，正常授權環境執行上述測試通過。測試時發現並修正cell欄位struct建構、空struct預配置及PowerShell5.1壓縮assembly載入問題。

沒有啟動本機正式訓練、真實飛行評估、pool或遠端連線；沒有證明實際六workers/GPU長跑、升階或收斂成功。完整流程仍待使用者遠端執行。模型、ZIP、完整日誌與使用者簡報均不加入Git。
