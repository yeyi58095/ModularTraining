# 專案背景與工作規則

## 來源與獨立定位

- 使用者於 2026-10-09 確認，本專案是**複製**出來的，不是搬移；原資料夾仍存在。
- 原始來源：`D:\daniel\GradSchool\0-Beginner\Paper\Flower\Deep Reinforcement Learning\ModularTraining`。
- 現在的獨立專案：`D:\daniel\GradSchool\0-Beginner\ModularTraining`，位置在 Flower 所在的 Paper 資料夾之外。
- 使用者於 2026-10-09 告知已自行將此獨立專案放上 GitHub；本機也已有 Git repository。這不代表授權代理自行 commit 或 push。
- Flower 提供研究背景與原始實作參考；不要將其路徑當成本專案的執行依賴，也不要假設兩邊後續仍同步。
- 使用者已授權讀取 `D:\daniel\GradSchool\0-Beginner\Paper\Flower`。此授權不包含修改來源資料夾。

## 實作注意事項

- 路徑應從程式／專案所在位置推導，避免硬編碼本機絕對路徑或依賴 Flower 的相對位置。
- 訓練入口是 `retry.m`；模型定義在 `+trainingmodels/`，獨立執行引擎在 `runtime/`。
- 新課程實驗資料在 `experiments/<課程>/runs/<實驗>/`；非課程與既有實驗保留 `+trainingmodels/<模型>/runs/<實驗>/`。複製的舊設定可能包含來源絕對路徑，續訓前需確認其指向。
- 不要擅自啟動、終止訓練或修改活動中的 runtime。
- 準備 GitHub 時遵循 `.gitignore`，不要自動納入訓練成果、checkpoint、日誌或快取。

## Reward 畫圖工具

- 根目錄的 `plot_training_rewards.py` 移植自 Flower 的 `Deep Reinforcement Learning/Simulink/plot_training_rewards.py`。
- 已調整為搜尋本專案 `experiments/<課程>/runs/`、模型的 `runs/` 與舊 `sessions/`，無須讀取 Flower。
- 使用 Python 與 matplotlib，讀取實驗內 `attempt_*/stdout.log`，輸出 `reports/reward_history.png` 與 `.csv`。
- 相同 episode 重複出現時採用較新 attempt 的紀錄；`--watch` 定期更新圖表，不控制訓練程序。

## 雙機與診斷分享（2026-10-09）

- 使用者有宿舍與實驗室兩台電腦；本次提供的 387,512 episodes／388 attempts reward 圖來自實驗室，不代表目前本機已有該實驗日誌。
- 圖中約 18 萬回合後長期低 reward 是待調查的觀察，不能直接歸因於 learning rate、LSTM 或 checkpoint 損壞。
- 用根目錄 `export_training_report.py <實驗資料夾> --machine lab`（或 `dorm`）產生 `<實驗資料夾>/reports/report.json`，作為可提交 GitHub 的精簡診斷紀錄。
- 完整訓練日誌、MAT checkpoint、快取留在產生資料的電腦；`.gitignore` 只放行指定結構的精簡報告。匯出不等於授權 commit、建立遠端或 push。
- 分享報告不等於搬移可續訓實驗。跨機續訓要另行確認 checkpoint 與 control.json 路徑，尤其 diagnosticDir 可能仍指向舊電腦。
- 匯出器獨立於 runtime，不修改訓練或自動停訓；當下程式指紋不能當作歷史執行版本的證明。
- 架構審視、限制與本次工作紀錄見 `docs/review-2026-10-09.md`；分享方式見 `reports/README.md`。

## Worker 與學習退步處理（2026-10-09 後續）

- 使用者希望同一段訓練立即使用可用的 n 個 MATLAB workers，而非只在下一次 attempt 降級。
- `retry(workers=6,minWorkers=1)` 現在以 `[minWorkers,workers]` 範圍建立 pool；成功取得 n 個後，在同一 attempt 使用 n 個，seed 數量亦依實際 pool 大小。`minWorkers=workers` 可要求固定數量。
- 範圍建池不等於保留未完成的連線；pool 整體建立失敗／卡住時仍走 supervisor 的失敗恢復與 watchdog。fallbackWorkers 作為失敗後的上限備援，不得低於 minWorkers。
- `learning_health.py` 在匯出報告時依連續區間計算疑似退步，預設只診斷，不自動停訓、回滾或改超參數。單次匯出不會持續監控。
- 預設門檻是待驗證的工程規則，不能當成 PPO 故障或 learning rate 過大的證明。策略及實作範圍見 `docs/learning-health.md`。
- 本機修改不會自動同步實驗室；更新實驗室 runtime 前應先確認該副本沒有活動訓練。

## JSON 分階段課程（2026-10-09）

- 使用者確認階段之間沿用同一個 agent，只改軌跡與訓練條件；模型放在 JSON 最外層。不要擅自把階段切換改成重新初始化模型。
- 新入口：`retry(curriculum="curricula/fixed_to_random.json",start=false)` 可建立計畫與輸入快照；`curriculum_plan(...)` 只檢查設定。使用者未授權啟動正式訓練。
- 支援內建固定路徑、MAT 軌跡和 random 軌跡。兩個 MAT 輸入的模板是 `curricula/two_mat_then_random.example.json`；使用者尚未提供實際軌跡1／軌跡2，不能假設檔案存在或變數格式相容。
- 條件支援 all/any、階段回合數、平均 reward／steps 及達指定步數比例；詳見 `docs/curriculum.md`。範例門檻只是示範，不是已驗證的論文復現參數。
- 條件只使用 checkpoint 保存的歷史，在存檔邊界切換；`max_episodes` 是當階段預算，`on_limit=pause` 保存後暫停，只有明確指定 advance 才按預算換階段。
- 每個實驗保存 `curriculum.json`、`curriculum_assets/`、`curriculum_state.json`、`curriculum_outcome.json`。已有 checkpoint 卻遺失階段狀態時拒絕猜測，不可隨意刪除狀態或改寫課程快照。
- 課程模式的過關條件以 JSON 為準，不接受另外傳入 targetReward；既有非課程實驗維持原流程。不要把既有普通實驗直接改旗標當成課程實驗。
- `+trainingcurriculum/` 屬執行程式，與 runtime 一樣不得在活動訓練期間修改。MAT 輸入不會自動納入 Git，沿用原忽略規則。
- 已通過合成歷史、入口假引擎、設定與報告測試；2026-10-09 亦在使用者授權下完成 CPU／1 worker 的真實 Simulink 三階段短測，見 `docs/validation-2026-10-09.md`。不能將其視為長期收斂或多 worker 驗證。

## 六階段訓練方案與短測（2026-10-09）

- `experiments/progressive_v1/curriculum.json`：直線 → 平緩 S 彎 → 固定轉彎 → random 無風 → 小風擾 → 完整風擾，沿用 ppo_lstm128。設計、起始門檻、限制與操作見 `docs/training-plan-v1.md`。
- `prepare_progressive_training()` 只生成可重建的 MAT 輸入並檢查設定，不啟動訓練；兩台電腦各自執行即可。不同內容的既有 MAT 不會被覆寫。
- 每階段使用最低回合數與連續三個 100 回合區間表現門檻，預算用盡 pause。數值尚未經長訓練校準；不宣稱能防止所有退步，learning_health 仍只在匯出時計算。
- 使用者這次授權短時間真實測試；`tests/test_curriculum_end_to_end.m` 已完成固定 → MAT → random 各一回合，總計 525 步、約 434 秒，確認跨階段 actor／critic 權重接續。測試已退出，沒有啟動正式六階段長訓練。
- 獨立 evaluator、最佳評估 checkpoint 選擇、可設定 root seed、退步自動停訓／回滾尚未實作；不要把規劃文件中的後續建議當成現有功能。

## 實驗室正式設定與提交（2026-10-09）

- 使用者本次明確要求 commit／上傳這批訓練方案，並準備遠端 6 workers＋GPU 設定；不在本機測試此組合或啟動正式訓練。
- `configs/lab_gpu6.json` 保存 retry 參數，使用 progressive_v1 課程、workers=6、minWorkers=1、device=gpu；仍維持當次有 n 個可用就先用 n 個的策略。操作步驟見 `docs/lab-start.md`。
- 執行參數 JSON 透過 jsondecode 與 namedargs2cell 傳入 retry；在專案根目錄執行。不要將硬體參數混入嚴格驗證的 curriculum schema。
- 實驗室回報 Java 將相對課程路徑解析到 System32；retry 已改為先從自身專案根目錄建立絕對路徑，再 canonicalize，resume 同樣處理。不要直接以 java.io.File(relative).getCanonicalPath() 解析使用者路徑。原 CPU 短測用絕對路徑，未涵蓋這項啟動差異。

## 課程分類與活動實驗保留（2026-10-10）

- 使用者希望以課程管理實驗、模型為課程參數。標準 curriculum.json 入口按父課程資料夾名稱存入 experiments；其他獨立 JSON 按檔名分類；同名計畫共用分類但各有唯一實驗 ID。
- 實驗室的 20261009_201547 實驗仍在舊目錄且使用者希望保留；禁止為結構調整而搬移或修改活動實驗。續訓始終依指定目錄原位進行。
- 畫圖新增由 curriculum_state.json 讀取的橘色 stage 分界與軸下方標籤；灰線為 attempt。可單獨更新 Python 畫圖檔並重啟畫圖工具，完整執行程式更新則等訓練退出後進行。
- 操作與備份限制見 docs/curriculum-layout.md；此次只做無訓練驗證，不代表遠端模型已備份或可安全搬移。
- 使用者後續回報實驗室 attempt 8 已 STOP，並要求把此次模型接續到新架構、上傳修改。migrate_training_session.ps1 僅對已停止且可取得鎖的實驗完整複製與逐檔 SHA256 驗證，原件保留；新副本的控制路徑修正，歷史紀錄不改寫。verify_training_session 在 MATLAB 唯讀檢查可用 checkpoint 及階段位置後，才由使用者 retry(resume=新位置)。不得在兩份副本同時續訓。
- 畫圖 stage 缺失修正：MATLAB jsondecode/jsonencode 會將 singleton struct array 重新編碼為單一 object，completed 必須兼容 list／object；不可據此認定階段歷史遺失。PNG 使用同目錄暫存檔完成後替換，watch 遇 OSError 會提示並重試；不修改訓練狀態。

## Stage 3 低分調查（2026-10-10）

- 使用者已停止實驗室 attempt 25 並提供精簡報告，日誌觀察到 12616 回合。詳見 docs/lab-regression-2026-10-10.md；此回合數不是已驗證的 checkpoint 進度。
- Stage 3 從 6101 開始；約 10700–10800 的下降在 attempt 22 內（10101–11100、4 workers），未與換階段／重啟邊界重合。最近 1000 回合平均步數 173.56，87.9% 少於 256 步，不能僅視為畫圖現象。
- 根因尚未證實；先保留 6100、下跌前約 10600 和最近可用 checkpoint 候選。獨立評估與分支恢復尚未實作，勿直接改課程狀態或覆蓋 checkpoint 作回滾，也未授權重新啟動訓練。

## 課程工作區與每次實驗報告（2026-10-10）

- 正式課程定義移至 experiments/progressive_v1/curriculum.json，prepare_progressive_training 產生同層 assets/；curricula/ 保留其他範例。舊 progressive_v1 入口由 resolve_curriculum_path 相容轉址。
- curriculum_state.json 是各 run 的實際進度，必須留在 runs/<session>/；頂層只放共享定義，既有 run 的課程和輸入快照不改寫。
- 圖表與精簡報告預設輸出到各 run/reports/。Git 僅放行頂層 curriculum.json 及 run/reports/report.json；MAT、完整日誌、PNG、CSV 仍忽略。
- organize_training_reports.ps1 在停止狀態與排他鎖下複製舊報告和圖表，比對雜湊、保留原件；相同檔案可重跑，不同目的檔拒絕覆蓋。已遷移的 run 不要重跑完整 migrate_training_session。
- 使用者明確授權本次架構修改、commit 與 push；沒有授權重啟目前因 Stage 3 退步停止的實驗。驗證使用 Python、PowerShell 合成測試與 MATLAB start=false，不代表長訓練收斂驗證。

## 停訓 checkpoint 比較（2026-10-10 後續）

- compare_training_checkpoints(sessionDir) 預設比較 6100、10600 及最新存檔，在快照前三階段各做一次 CPU 純 sim；不啟動 pool、不 train、不 prepare 課程或回滾。只支援無風 MAT／fixed_builtin。
- 使用者確認實驗室 6100 與 10600 存在，但尚未評估。不可把本機既有短測 checkpoint 的模擬當成實驗室結果。
- 結果在每次 run/reports/evaluation_<時間>_<唯一碼>/；逐次 JSON 和 MAT traces 都受 Git 忽略，可請使用者貼 evaluation.results。預設固定條件單 seed 診斷不是泛化成功率。
- 工具鎖住已停止實驗，檢查原 checkpoint SHA256 及 sim 前後權重。IsDone 不是具體物理終止原因，observation7_rms 不是已確認公尺單位誤差。分支恢復、自動最佳模型選擇與停訓仍未實作。
- 操作與測試見 docs/checkpoint-comparison.md；使用短系統暫存路徑做 Simulink 快取，避免 Windows 260 字元限制。不要在原 checkpoint 裡改探索模式／裝置後另存覆寫；工具只改記憶體內 agent。
