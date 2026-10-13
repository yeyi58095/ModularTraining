# 本機真實訓練驗證：2026-10-09

使用者授權短時間試跑後，在本機 MATLAB R2024b 執行 `tests/test_curriculum_end_to_end.m`。本次使用真實 FAFA Simulink 環境、PPO agent、CPU、1 個 Processes worker，沒有使用假引擎或假 pool。

實驗 ID：`20261009_182703_tp24591b71_9769_4162_a931_20fd74f3a780`，位於 `+trainingmodels/ppo_lstm128/runs/`。2026-10-09 18:27 至 18:34（Asia/Taipei），supervisor 執行約 434.1 秒，含三次程序啟動／建池／模擬／存檔。測試與 supervisor 均成功退出；結束後確認沒有剩餘 MATLAB、checkpoint supervisor 或 watchdog 程序。

| Attempt | 軌跡 | 累計回合 | Reward | 步數 | 實際 workers |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | 內建固定 | 1 | 108.385653 | 133 | 1 |
| 2 | 生成的 MAT 直線 | 2 | 108.274919 | 133 | 1 |
| 3 | Random | 3 | 193.543365 | 259 | 1 |

測試專用門檻是每階段完成一回合，三個階段都是無風。驗證成功存檔 `Agent_Success.mat`、累計三回合且 reward 有限、課程完成狀態、每次 attempt 的 stage／resumeFile，以及 episode_workers.csv 的三筆紀錄。另逐一讀取上一段 Agent_Final 與下一段 Agent_Initial，確認 actor 和 critic 的 learnable parameters 完全相同，證明階段交接沒有重新初始化權重。

本機完整測試收據在 `tests/output/curriculum-smoke-latest.json`；此目錄與實驗 MAT／日誌均受 Git 忽略，本文件保留可分享的結果。後續重跑會更新 latest 收據，實驗則另建獨立目錄。

另實際執行 `prepare_progressive_training()` 兩次，確認輸入生成具冪等性；兩條軌跡均為 4001×3、S 彎速度模長為 15 m/s，六階段 JSON 通過驗證，`retry(...,start=false)` 成功建立課程及輸入快照。這份六階段正式實驗沒有啟動。

本次證明真實流程可執行並可跨階段接續，沒有驗證收斂、長期穩定性、GPU、多 worker、資源不足時實際建池降級，或六階段門檻的適當性。三回合也不足以證明有效策略更新。S 彎與有風條件尚未做真實訓練短測；其設定／輸入已驗證。不得把測試用「完成」視為 UAV 任務已學會。
