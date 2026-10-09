# 專案背景與工作規則

## 來源與獨立定位

- 使用者於 2026-10-09 確認，本專案是**複製**出來的，不是搬移；原資料夾仍存在。
- 原始來源：`D:\daniel\GradSchool\0-Beginner\Paper\Flower\Deep Reinforcement Learning\ModularTraining`。
- 現在的獨立專案：`D:\daniel\GradSchool\0-Beginner\ModularTraining`，位置在 Flower 所在的 Paper 資料夾之外。
- 使用者希望 ModularTraining 成為獨立的新專案，未來會 push 到 GitHub。目前這項規劃不代表已授權建立遠端儲存庫或 push。
- Flower 提供研究背景與原始實作參考；不要將其路徑當成本專案的執行依賴，也不要假設兩邊後續仍同步。
- 使用者已授權讀取 `D:\daniel\GradSchool\0-Beginner\Paper\Flower`。此授權不包含修改來源資料夾。

## 實作注意事項

- 路徑應從程式／專案所在位置推導，避免硬編碼本機絕對路徑或依賴 Flower 的相對位置。
- 訓練入口是 `retry.m`；模型定義在 `+trainingmodels/`，獨立執行引擎在 `runtime/`。
- 新實驗資料在 `+trainingmodels/<模型>/runs/<實驗>/`。複製的舊設定可能包含來源絕對路徑，續訓前需確認其指向。
- 不要擅自啟動、終止訓練或修改活動中的 runtime。
- 準備 GitHub 時遵循 `.gitignore`，不要自動納入訓練成果、checkpoint、日誌或快取。

## Reward 畫圖工具

- 根目錄的 `plot_training_rewards.py` 移植自 Flower 的 `Deep Reinforcement Learning/Simulink/plot_training_rewards.py`。
- 已調整為搜尋本專案模型的 `runs/` 與舊 `sessions/`，無須讀取 Flower。
- 使用 Python 與 matplotlib，讀取實驗內 `attempt_*/stdout.log`，輸出 `reward_history.png` 與 `.csv`。
- 相同 episode 重複出現時採用較新 attempt 的紀錄；`--watch` 定期更新圖表，不控制訓練程序。

## 雙機與診斷分享（2026-10-09）

- 使用者有宿舍與實驗室兩台電腦；本次提供的 387,512 episodes／388 attempts reward 圖來自實驗室，不代表目前本機已有該實驗日誌。
- 圖中約 18 萬回合後長期低 reward 是待調查的觀察，不能直接歸因於 learning rate、LSTM 或 checkpoint 損壞。
- 用根目錄 `export_training_report.py <實驗資料夾> --machine lab`（或 `dorm`）產生 `reports/<machine>/<session>/report.json`，作為可提交 GitHub 的精簡診斷紀錄。
- 完整訓練日誌、MAT checkpoint、快取留在產生資料的電腦；`.gitignore` 只放行指定結構的精簡報告。匯出不等於授權 commit、建立遠端或 push。
- 分享報告不等於搬移可續訓實驗。跨機續訓要另行確認 checkpoint 與 control.json 路徑，尤其 diagnosticDir 可能仍指向舊電腦。
- 匯出器獨立於 runtime，不修改訓練或自動停訓；當下程式指紋不能當作歷史執行版本的證明。
- 架構審視、限制與本次工作紀錄見 `docs/review-2026-10-09.md`；分享方式見 `reports/README.md`。
