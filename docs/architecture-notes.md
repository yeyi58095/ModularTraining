# 架構圖核對與閱讀說明

核對日期：2026-10-10。架構 HTML／JSON 已依目前程式更新；此次未啟動或修改訓練。舊簡報中的架構頁不會因 HTML 更新而自動同步。

## 課程驅動的執行順序

1. `configs/lab_gpu6.json` 指定硬體、存檔與重試參數，引用 `experiments/progressive_v1/curriculum.json`。課程指定模型、軌跡、風場、過關條件與各階段預算；模型定義仍在 `+trainingmodels/`。
2. `retry.m` 新建 `experiments/<課程>/runs/<實驗 ID>/`，保存 control、curriculum、軌跡、model 與 model_source 快照。非課程實驗保留模型目錄分類；resume 依完整實驗路徑原位接續。
3. PowerShell supervisor 啟動 `checkpoint_attempt.m`。它選取有效 checkpoint，透過 `training.m` 取得模型建立／驗證回呼，並用 `trainingcurriculum.prepare` 檢查課程歷史、取得目前階段環境。課程結束或預算暫停時不啟動 engine。
4. `training_engine.m` 載入原 agent 與訓練歷史或建立新 agent；建立 pool，讓 workers 執行 `FAFA_Simulation.slx`。同一課程跨階段沿用 agent，沒有重新初始化網路。
5. 實驗室設定每 100 回合存 checkpoint、每段最多追加 1000 回合。段落結束保存 Agent_Final，再按該階段保存的歷史判斷；達標於下一個 attempt 切換階段，預算用盡則依 on_limit 處理。最後階段達標才發布課程成功。
6. 課程模式不採舊的全實驗 reward >=2900 成功規則。progressive_v1 每階段結合最低回合數、連續三個 100 回合區間 reward 與步數指標；這些門檻仍待長期驗證。

## Worker 與失敗恢復

- lab_gpu6 目標 6、最低 1，使用 parpool 的數量範圍；只有成功返回的 pool 才能訓練。「Connected to 5 of 6」不是已可使用的 5-worker pool。
- pool 建立失敗後，後續 attempt 依 lab_gpu6 的 4 → 2 → 1 備援重建。不是保留未完成的部分連線。一般 retry 預設備援仍為 [4 2]，不要混淆設定檔與函式預設。
- 成功建池後，下一段恢復目標數量。狀態中的 running 只代表程序執行中；Pool ready 與 Episode 日誌才證明後續進展。
- 預設啟動逾時 600 秒、日誌無活動逾時 1800 秒；連續無進度失敗達上限便暫停。STOP 中止程序，保留已保存 checkpoint，不會額外先保存尚未完成的回合。

## 實驗、圖表與遷移

- 診斷存於實驗 diagnostics／attempt 目錄。`plot_training_rewards.py` 讀 stdout 回合資料，讀 curriculum_state.json 的實際分界，在 run/reports/ 產生有 Stage 標籤的 reward 圖。灰線是 attempt，橘線是 stage。
- `export_training_report.py` 在 run/reports/ 產生可分享的小型 report.json；learning_health 是匯出時計算的規則式診斷，沒有持續監控、自動停訓或回滾。完整 checkpoint 仍需另行保留。
- `migrate_training_session.ps1` 只接受已停止、可取得排他鎖的實驗；複製全部資料、比對 SHA256、修正新副本控制路徑，保留原件。`verify_training_session.m` 讀回有效 PPO checkpoint 與階段位置，不啟動訓練；之後以 retry(resume=新位置) 接續。
- 歷史日誌中的舊路徑不重寫。不能同時續跑新舊副本，不能在活動訓練時搬移或改 runtime。

## 圖的抽象範圍與證據

- 箭頭表示主要控制／資料關係，不全是函式呼叫；課程規劃器會將階段環境回傳給 attempt，圖中省略返回箭頭。引擎段末另呼叫 outcome 判斷條件。
- 「診斷、曲線與精簡報告」將資料與離線工具合併呈現：supervisor 收集日誌，但不會自動啟動畫圖或匯出報告。Database 圖例表示檔案資料，不是資料庫服務。
- 模型快照不包含整套 runtime；同一實驗不是任意版本執行程式的完整封裝。獨立 evaluator、最佳評估模型選擇、退步自動回滾尚未實作。
- 對照來源：retry.m、training.m、configs/lab_gpu6.json、experiments/progressive_v1/curriculum.json、+trainingcurriculum/prepare.m 與 outcome.m、runtime/checkpoint_supervisor.ps1、runtime/training_engine.m、migrate_training_session.ps1、verify_training_session.m、plot_training_rewards.py。
- 本次使用 archify 技能產生 architecture 類型 HTML；繁體中文內容，固定 Viewer UI 與 HTML 語系為英文。
- architecture-receipt.json：9/9 靜態 artifact 檢查通過，composition 0 errors／0 warnings，包含 specification 與 artifact SHA256／bytes。
- architecture.visual-check.json：真實 Chrome 對 1440×900、1600×1000、1920×1080、2048×1320 的測量均無水平或垂直溢出；明暗截圖已產生。
- 人工影像檢閱：檢查四張端點尺寸的明暗截圖，節點、箭頭、卡片與圖例未見裁切或遮擋；此判斷獨立於自動收據的 visualReview=pending，未改寫該欄位。

頂層 experiments/<課程>/curriculum.json 是共享課程定義，assets/ 是輸入；各 run 的 curriculum_state.json 是獨立進度。organize_training_reports.ps1 可複製整理舊報告，保留原件與模型。
