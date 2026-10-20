# MATLAB 準備與稽核工具

MATLAB 切到專案根目錄（或 `addpath` 專案根目錄），用套件名稱呼叫，不需 `genpath`。

| 工作 | 入口 |
| --- | --- |
| 八階段輸入準備 | `trainingtools.prepare_progressive_v2_training()` |
| 第三組從頭驗證的開訓前檢查 | `trainingtools.preflight_round3()` |
| 暫停第三組16000／17200配對診斷 | `trainingtools.review_round3(runDir)` |
| 保存歷史shadow重播（零自動動作） | `trainingtools.shadow_learning_review(runDir,17200)` |
| 獨立SAC試驗準備（不啟動） | `trainingtools.prepare_sac_trial()` |
| 連續飛行完整情境重播（非標準評估） | `trainingtools.simulate_continuous_flight(checkpoint,scenarioFile,stageId,seed)` |
| 建立獨立連續飛行模擬 SLX（已存在則拒絕覆寫） | `trainingtools.build_continuous_flight()` |
| 舊六階段輸入準備 | `trainingtools.prepare_progressive_training()` |
| 恢復分支準備 | `trainingtools.prepare_recovery_training(...)` |
| 續訓來源／獎勵稽核 | `trainingtools.audit_training_resume(...)`、`trainingtools.audit_training_rewards(...)` |
| 離線 reward 校準 | `trainingtools.calibrate_training_rewards(...)` |
| 停止實驗驗證 | `trainingtools.verify_training_session(...)` |
| 歷史 Stage6 批次評估 | `trainingtools.review_stage6_checkpoints(...)`、`trainingtools.review_stage6_candidates(...)` |

根目錄保留 `retry`、`training_status`、`curriculum_plan`、`compare_training_checkpoints` 等日常入口與必要適配函式。此套件的既有函式僅變更位置與專案根路徑推導，不變更訓練、評估或恢復語意。
