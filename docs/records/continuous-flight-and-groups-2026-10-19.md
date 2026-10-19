# 連續模擬副本與實驗組別入口

使用者更正先前 isDone 說法：訓練時要結束 episode；非訓練的「實飛」在本次明確指 Simulink 連續飛行模擬，希望偏差超標後繼續觀察，不是實體飛機部署。先前「非訓練接 Stop Simulation」的規則已撤回。新增資料夾名稱全部使用英文。

## 連續模擬

- 新增 simulations/continuous_flight/FAFA_ContinuousFlight.slx，從固定 spatial_v2 複製，不修改來源、runtime 或既有 run。
- RL Agent 第3輸入接 boolean false；原 isdone 子系統與全部判定邏輯留存，輸出改送 To Workspace 的 isDoneDiagnostic。不是只取消距離條件；所有原 isDone 原因都只作紀錄，不觸發此副本的 episode 終止。
- StopTime 設為 300 秒；使用者停止、模擬錯誤與有限時長仍有效。此副本不是無限運行承諾。
- 21 個 Stateflow 嵌入 MATLAB 程式內容與來源逐一相同。來源 SHA 保持 997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557，副本 SHA 見同目錄 manifest.json。
- MATLAB 載入與結構測試通過：原模型 isdone→RL Agent 接線保持、副本 RL Agent 接 false、原 done 接診斷、有限時長、agent 變數一致、程式內容相同、重建拒絕覆寫。未執行完整飛行 sim 或 train，不能宣稱工作區輸入已完整準備、飛行穩定或超標後可恢復。
- 副本仍需選定 Agent_Stage2 與路徑／風場等工作區輸入。不得作為標準評估或用「跑滿」宣稱通過原終止門檻；不加入 trainingenv registry。

## 組別查找

- experiments/progressive_v2/groups/group_02_recovery：先列出成功分支及 recovery.json 指定的直接父 run；不猜測截圖中更早資料夾的歸屬。
- groups/group_03_fresh：第三組 20261019_164959_tpc77cb232_0370_4212_a632_e1644201eec0。尚未收到其實際啟動狀態，不因本紀錄而重複啟動。
- tools/link_experiment_groups.ps1 預覽後以 -Apply 在每組 runs/ 建本機資料夾 .lnk。實際 run 路徑保持不變，沒有資料複製、junction 或改 control 快照；新階層是查找入口。
- 本機沒有上述實驗室的完整 run，因此實際預覽只回報 Missing，不建立假 run。實驗室需由使用者執行以產生符合該機路徑的捷徑。
- 合成測試通過：預覽不寫、正確目標、缺來源不建捷徑、重跑不改捷徑、run 雜湊不變、異常既有捷徑保留與路徑穿越拒絕。group README／JSON 可進 Git，捷徑與模型 MAT 仍忽略。

本次只新增模型副本、工具、組別 metadata 與文件；未變更訓練程式或既有環境。使用者原 PPTX／ZIP 變更保留且不提交。測試日誌在 tests/output/continuous-flight-model.log；測試只針對本次範圍。
