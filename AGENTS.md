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
- 架構審視、限制與本次工作紀錄見 `docs/records/review-2026-10-09.md`；分享方式見 `reports/README.md`。

## Worker 與學習退步處理（2026-10-09 後續）

- 使用者希望同一段訓練立即使用可用的 n 個 MATLAB workers，而非只在下一次 attempt 降級。
- `retry(workers=6,minWorkers=1)` 現在以 `[minWorkers,workers]` 範圍建立 pool；成功取得 n 個後，在同一 attempt 使用 n 個，seed 數量亦依實際 pool 大小。`minWorkers=workers` 可要求固定數量。
- 範圍建池不等於保留未完成的連線；pool 整體建立失敗／卡住時仍走 supervisor 的失敗恢復與 watchdog。fallbackWorkers 作為失敗後的上限備援，不得低於 minWorkers。
- `learning_health.py` 在匯出報告時依連續區間計算疑似退步，預設只診斷，不自動停訓、回滾或改超參數。單次匯出不會持續監控。
- 預設門檻是待驗證的工程規則，不能當成 PPO 故障或 learning rate 過大的證明。策略及實作範圍見 `docs/guides/learning-health.md`。
- 本機修改不會自動同步實驗室；更新實驗室 runtime 前應先確認該副本沒有活動訓練。

## JSON 分階段課程（2026-10-09）

- 使用者確認階段之間沿用同一個 agent，只改軌跡與訓練條件；模型放在 JSON 最外層。不要擅自把階段切換改成重新初始化模型。
- 新入口：`retry(curriculum="curricula/fixed_to_random.json",start=false)` 可建立計畫與輸入快照；`curriculum_plan(...)` 只檢查設定。使用者未授權啟動正式訓練。
- 支援內建固定路徑、MAT 軌跡和 random 軌跡。兩個 MAT 輸入的模板是 `curricula/two_mat_then_random.example.json`；使用者尚未提供實際軌跡1／軌跡2，不能假設檔案存在或變數格式相容。
- 條件支援 all/any、階段回合數、平均 reward／steps 及達指定步數比例；詳見 `docs/guides/curriculum.md`。範例門檻只是示範，不是已驗證的論文復現參數。
- 條件只使用 checkpoint 保存的歷史，在存檔邊界切換；`max_episodes` 是當階段預算，`on_limit=pause` 保存後暫停，只有明確指定 advance 才按預算換階段。
- 每個實驗保存 `curriculum.json`、`curriculum_assets/`、`curriculum_state.json`、`curriculum_outcome.json`。已有 checkpoint 卻遺失階段狀態時拒絕猜測，不可隨意刪除狀態或改寫課程快照。
- 課程模式的過關條件以 JSON 為準，不接受另外傳入 targetReward；既有非課程實驗維持原流程。不要把既有普通實驗直接改旗標當成課程實驗。
- `+trainingcurriculum/` 屬執行程式，與 runtime 一樣不得在活動訓練期間修改。MAT 輸入不會自動納入 Git，沿用原忽略規則。
- 已通過合成歷史、入口假引擎、設定與報告測試；2026-10-09 亦在使用者授權下完成 CPU／1 worker 的真實 Simulink 三階段短測，見 `docs/records/validation-2026-10-09.md`。不能將其視為長期收斂或多 worker 驗證。

## 六階段訓練方案與短測（2026-10-09）

- `experiments/progressive_v1/curriculum.json`：直線 → 平緩 S 彎 → 固定轉彎 → random 無風 → 小風擾 → 完整風擾，沿用 ppo_lstm128。設計、起始門檻、限制與操作見 `docs/guides/training-plan-v1.md`。
- `prepare_progressive_training()` 只生成可重建的 MAT 輸入並檢查設定，不啟動訓練；兩台電腦各自執行即可。不同內容的既有 MAT 不會被覆寫。
- 每階段使用最低回合數與連續三個 100 回合區間表現門檻，預算用盡 pause。數值尚未經長訓練校準；不宣稱能防止所有退步，learning_health 仍只在匯出時計算。
- 使用者這次授權短時間真實測試；`tests/test_curriculum_end_to_end.m` 已完成固定 → MAT → random 各一回合，總計 525 步、約 434 秒，確認跨階段 actor／critic 權重接續。測試已退出，沒有啟動正式六階段長訓練。
- 獨立 evaluator、最佳評估 checkpoint 選擇、可設定 root seed、退步自動停訓／回滾尚未實作；不要把規劃文件中的後續建議當成現有功能。

## 實驗室正式設定與提交（2026-10-09）

- 使用者本次明確要求 commit／上傳這批訓練方案，並準備遠端 6 workers＋GPU 設定；不在本機測試此組合或啟動正式訓練。
- `configs/lab_gpu6.json` 保存 retry 參數，使用 progressive_v1 課程、workers=6、minWorkers=1、device=gpu；仍維持當次有 n 個可用就先用 n 個的策略。操作步驟見 `docs/guides/lab-start.md`。
- 執行參數 JSON 透過 jsondecode 與 namedargs2cell 傳入 retry；在專案根目錄執行。不要將硬體參數混入嚴格驗證的 curriculum schema。
- 實驗室回報 Java 將相對課程路徑解析到 System32；retry 已改為先從自身專案根目錄建立絕對路徑，再 canonicalize，resume 同樣處理。不要直接以 java.io.File(relative).getCanonicalPath() 解析使用者路徑。原 CPU 短測用絕對路徑，未涵蓋這項啟動差異。

## 課程分類與活動實驗保留（2026-10-10）

- 使用者希望以課程管理實驗、模型為課程參數。標準 curriculum.json 入口按父課程資料夾名稱存入 experiments；其他獨立 JSON 按檔名分類；同名計畫共用分類但各有唯一實驗 ID。
- 實驗室的 20261009_201547 實驗仍在舊目錄且使用者希望保留；禁止為結構調整而搬移或修改活動實驗。續訓始終依指定目錄原位進行。
- 畫圖新增由 curriculum_state.json 讀取的橘色 stage 分界與軸下方標籤；灰線為 attempt。可單獨更新 Python 畫圖檔並重啟畫圖工具，完整執行程式更新則等訓練退出後進行。
- 操作與備份限制見 docs/guides/curriculum-layout.md；此次只做無訓練驗證，不代表遠端模型已備份或可安全搬移。
- 使用者後續回報實驗室 attempt 8 已 STOP，並要求把此次模型接續到新架構、上傳修改。migrate_training_session.ps1 僅對已停止且可取得鎖的實驗完整複製與逐檔 SHA256 驗證，原件保留；新副本的控制路徑修正，歷史紀錄不改寫。verify_training_session 在 MATLAB 唯讀檢查可用 checkpoint 及階段位置後，才由使用者 retry(resume=新位置)。不得在兩份副本同時續訓。
- 畫圖 stage 缺失修正：MATLAB jsondecode/jsonencode 會將 singleton struct array 重新編碼為單一 object，completed 必須兼容 list／object；不可據此認定階段歷史遺失。PNG 使用同目錄暫存檔完成後替換，watch 遇 OSError 會提示並重試；不修改訓練狀態。

## Stage 3 低分調查（2026-10-10）

- 使用者已停止實驗室 attempt 25 並提供精簡報告，日誌觀察到 12616 回合。詳見 docs/research/lab-regression-2026-10-10.md；此回合數不是已驗證的 checkpoint 進度。
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
- 操作與測試見 docs/guides/checkpoint-comparison.md；使用短系統暫存路徑做 Simulink 快取，避免 Windows 260 字元限制。不要在原 checkpoint 裡改探索模式／裝置後另存覆寫；工具只改記憶體內 agent。

## 恢復試驗與自動暫停（2026-10-10 後續）

- 使用者貼回實驗室評估：6100／10600 在直線及 S 彎各 3000 步，固定轉彎為399／1578；12600 三項均138步。僅證明該固定條件下退步，10600 是三個候選中的恢復起點，不稱全歷史最佳。
- 新 prepare_recovery_training(parentSession) 預設用 configs/recovery_actor_half.json：10600、actor LR 乘0.5，其餘學習參數與課程不變。另建新 run、保留權重與歷史、記錄 recovery.json，不改父實驗，不自動訓練。model.json 與 agent optimizer rate 同步。
- 硬體沿用父 control；段落改100回合，總新增上限1000。段落與 seed 變化也是差異，不能把效果全歸因於 LR。以 retry(resume=新session) 才正式啟動。
- 新分支 training_guard.json：同階段100回合區間、參考 reward/steps 均>=500，連續3個區間 reward 與 steps 都低於參考的50%時，在保存後暫停；總預算到達亦暫停。training_guard_state.json 暫停保持鎖定，單純retry不繞過。
- health_candidates/CandidateN.mat 只是訓練區間候選，不是最佳評估模型。沒有自動回滾、改參數、重啟分支或週期獨立評估；手動 compare_training_checkpoints 仍可用。learning_health.py 與 runtime guard 不同，report.json 分別呈現。
- 本次使用既有本機 checkpoint、合成歷史與假引擎驗證，不啟動正式恢復訓練或 GPU／6 workers。配方、操作、限制見 docs/guides/recovery-training.md。
- 實驗室 recovery 在 11000 被 guard 暫停；比較 checkpoint 時報告寫入例外遮住原始錯誤。評估工具已改為預先綁定報告函式，保留 phase、原始堆疊，寫報告失敗不能取代原始例外。本機未重現實驗室最初錯誤，需依重新執行後的原始訊息調查；不要因此續訓或改 guard 狀態。
- 後續實驗室證實預先綁定 package handle 仍可能呼叫失敗；現改成入口內直接 catch/rethrow 與同檔 local JSON writer，不再使用 fail_evaluation 套件函式。切換 Simulink 快取／目錄與載入模型後補回 root/runtime 路徑。實際入口故障注入已驗證：移除 root 路徑後仍保存失敗報告、拋出原始模型錯誤；實驗室初始錯誤仍待確認。
- 實驗室後續完整評估成功：10600 步數3000/3000/1578，10700為133/134/133，11000均144；第一段100回合內已觀察到舊任務能力下降。audit_training_resume 唯讀核對既有 Agent_Initial 與其 resume 來源、主要設定及權重差異，不解析 optimizer 私有狀態、不自動續訓。單 seed 結果不證明根因，操作見 docs/guides/resume-audit.md。
- 使用者同意以診斷 ZIP／GitHub Release 附件跨機分享，不解除 MAT/log 忽略或重寫 Git 歷史。pack_training_diagnostics.ps1 只在停止狀態及排他鎖下選取 checkpoint、initial snapshot、evaluation traces 與設定日誌，產生 diagnostic_packages/ ZIP 並驗證逐檔 SHA256；不自動上傳、不啟動訓練，子集不能作完整續訓備份。實驗室打包和草稿附件流程見 docs/guides/diagnostic-package.md。
- 實驗室 ZIP 已由使用者複製回本機並通過38檔雜湊驗證。讀取 traces 並比對相同SHA256的模型後，確認本次提前終止對應模型 d>=50m，非roll±40度；observation7=d/30。10601–10700 同一 attempt 內表現逐步變差。根因仍未證實，尤其前約10秒 d=0 不可解讀為完美循跡；詳見 docs/research/lab-trace-findings-2026-10-10.md。未啟動訓練或模擬。
- 後續離線actor重播各自trace最大action誤差0；相同10600觀測前150步，10600/10700均值平均絕對差0.365。純函式驗證WindowManager首次valid在第100次(0.1秒取樣)，之前planner輸出單點導致guidance回傳假零誤差。首次valid候選僅在diagnostic_packages副本測試[1,100]，未改SLX或runtime，未證實是更新退步唯一根因；閉迴路候選比較尚未做，不得宣稱已修復收斂。
- 使用者後續要求修正初始化：runtime/FAFA_Simulation.slx的WindowManager改成首次呼叫及原週期發出valid，仍需完整window。只更改chart60一行；tests/test_window_startup從實際模型驗證[1,100,200]和短路徑拒絕。這是環境版本變更，不能把新舊分數直接合併；不改既有checkpoint/課程快照或自動續訓。操作見docs/guides/startup-path-fix.md。
- 初始化修正A/B：實驗室10600與10700各在原版/修正版直線seed101 CPU評估，上限200步；10600均200步，10700由原版133步IsDone變為修正版200步上限。四次權重及checkpoint SHA不變；無訓練，未證明3000步完成或長期收斂。新評估使用新模型SHA，不與歷史環境混為一談。
- 完整實驗室回報修正版10600/10700直線及S彎皆3000步，固定轉彎1578/1589；10700仍較大循跡誤差。使用者決定新run：configs/recovery_startup_fix.json從第一個recovery分支10600接續，來源LR必須2.5e-5，scale=1，不再減半；沿用stage3快照和硬體，100/段、上限1000。prepare記錄當下runtime模型/引擎SHA但不啟動。共用課程JSON不改，舊run不改；操作見docs/guides/startup-path-fix.md。
- 11600評估直線/S彎3000步、固定轉彎2673步。使用者決定先維持共同判讀訓練，合格後提醒整理純腳本另行重跑驗證；已設定本對話條件式提醒，未確認合格時保持安靜。跨夜配方configs/recovery_11600_overnight.json從20261010_201201分支11600另開run，新增10000（最終要求，取代5000），最多21600，LR不變、100/段、guard保留。不要自動解除退步停訓或宣稱一定跨夜/合格。

## Run 繼承與跨實驗畫圖（2026-10-10 記錄，2026-10-11 實作）

- 2026-10-10 原要求只記錄；2026-10-11 使用者授權實作畫圖與文件。plot_training_rewards.py 預設沿 recovery.json 的 parent_session／parent_episode 追溯，祖先只取到分支 checkpoint，子 run 只取接續後的新回合；不同 run 不套用較新 attempt 覆蓋規則。CSV 帶來源欄位，stage 橘線、接續點紫線、各 run 平均 reward 分色。
- --no-lineage 恢復單 run 畫法；--lineage-root 提供跨機搬移後的搜尋根目錄。同名來源不唯一、來源缺失、循環或錯誤繼承關係會提示，不猜測來源、不補資料。只讀日誌與 JSON、寫指定 PNG／CSV，不修改 checkpoint、課程、控制或訓練程式；訓練中可單獨更新畫圖檔並重啟畫圖程序。
- 圖例的 prepared_runtime_model_sha256 只證明 prepare 當時環境，configured avg window 來自當下 control，不是歷史執行證據。平均 reward 保留日誌值，不跨 run 重算；未知 reward 版本不能宣稱可直接比較。不實作所有分支比較或其他指標圖。操作、限制與合成測試見 docs/guides/run-lineage-proposal.md。

## Stage 5 配對評估（2026-10-11）

- 實驗室 21600 因 recovery_budget 暫停；前三項無風任務均跑滿，但 Stage 5 低分原因尚未證實。使用者授權下一步擴充評估，不授權續訓。
- compare_training_checkpoints 現支援 random 與課程風場；相同 seed 配對路徑，另外抽樣整數風，保存 scenarios 與逐次 traces，CPU 純 sim、不改 runtime/checkpoint/guard。操作見 docs/guides/stage5-evaluation.md。
- summary 提供樣本完成率及最差 reward trace；終端門檻證據不是 IsDone 分支因果證明。內部 turbulence seeds 沿用 SLX；多 seed 不等於獨立噪音時序，10 組診斷不代表合格。實驗室 21600 checkpoint 尚未在本機測試。
- 使用者提供完整20次Stage4/5評估ZIP：無風10/10、有風8/10；205/207在104.2/74.3秒達d≈50，動作反向接近路徑更新時點，未證實因果。純離線比對與限制見 docs/research/stage5-trace-findings-2026-10-11.md。
- diagnostics=true 只在暫存SLX副本啟用訊號記錄，新增位置、planner/window paths及guidance目標；原runtime/checkpoint不改。下一步實驗室重播205/207/210並核對原結果，保持訓練暫停。未授權自動重啟訓練。
- 詳細ZIP證實205/207失敗前地速16.3–16.4m/s、越過當前path末點，目標落到後方，valid更新後跳回前方；終端獨立折線距離與d一致。不能單凭此認定唯一根因。新增評估專用 guidanceVariant="endpoint_lookahead"，只在暫存副本沿末段切線補足lookahead，不動正式SLX/reward/IsDone。說明與A/B指令見 docs/research/endpoint-lookahead-candidate.md；尚未驗證21600候選效果，不得啟動續訓或宣稱修復收斂。
- 第一版候選在實驗室205有風改善至3000、207延至1145仍失敗；詳細trace確認109秒越出包圍範圍時outside分支退回舊終點。第二版 endpoint_lookahead_v2 僅對outside且最近點為末點、沿切線超越、側偏≤30m時延伸目標，其餘保留。不改正式模型；第二版21600效果仍待實驗室A/B，不可宣稱已解決。

## 第二版正式部署（2026-10-12）

- 實驗室第二版擴展測試43/43跑滿3000步，另原版新情境20/20；前三階段能力在單seed保留，Stage6未驗證，不代表整體合格。詳見docs/guides/endpoint-v2-training.md。
- 使用者授權正式納入修正、push並提供立即續訓指令。runtime SLX guidance 採用已評估第二版；不改reward/IsDone。新configs/recovery_21600_endpoint_v2.json從21600另開run，LR不變、100/段、新增10000至最多31600、guard保留、Stage5進度沿用。不得改寫父實驗或自行在本機啟動正式訓練。
- baseline現在表示正式第二版環境；候選函式拒絕重複套用，舊版guidance文字fixture只供測試。新舊環境分數不能全視為agent學習變化。prepare記錄新環境SHA；用戶自行在實驗室啟動。

## Stage6 有效歷史路徑候選（2026-10-13）

- 使用者提供兩個診斷ZIP並授權繼續隔離評估。380個manifest檔案及補充包SHA已驗證；本機首次使用實驗室31600checkpoint做CPU純sim，未訓練。工作區既有註解及文件重組修改保留，未提交。
- 確認guidance的path_CTE包含global_path未填入零列，末點可能錯連(0,0)。新增guidanceVariant="valid_history"僅在評估副本截到path_length，正式SLX未改。27次評估：baseline4次重現；候選小風10/10、完整風6/10、前三階段3/3，完整風失敗步數2596/998/695/730變2715/1111/1417/730，並非已修復合格。
- 剩餘失敗有真實偏離與path更新後目標轉向；不可僅放寬門檻、改小d或盲目續訓。後續需評估前方路徑不足與時間window/實際地速進度的關係，不能未說明便改任務語義。來源、證據與限制見docs/records/stage6-history-review-2026-10-13.md。

## Stage 6 空間循跡部署（2026-10-13）

- 使用者明確選擇「沿指定路徑穩定飛行，可依飛機進度更新路段」，授權此任務語義變更；不再宣稱追蹤按原時序移動的目標。
- 正式 SLX 修正有效歷史範圍，WindowManager 改成局部單調進度、距尾約40點時提前提供連續下一段。重疊 window 候選退步，未部署；未改 reward 公式、終止門檻或 PPO 參數。
- 實驗室 Agent31600 的本機 CPU 純sim：Stage5 10/10、Stage6既有10/10、新20/20、前三階段3/3，共43個不同組合全跑滿3000。四例獨立原始路線距離RMS8.86–10.57m；全程最大50m皆在初始t=0，10秒後最大18.50–21.28m。這不是完整合格或長訓練收斂證明。
- configs/recovery_31600_progress_window.json 鎖定新 SLX SHA，31600另開分支、LR不變、100/段、最多新增10000至41600，guard保留。只提供實驗室啟動指令，不自行啟動正式訓練。保留舊階段紀錄不代表新環境已逐階訓練驗證；未來合格後仍需純腳本從頭重跑。
- 操作及完整證據見 docs/guides/stage6-progress-training.md、docs/records/stage6-progress-validation-2026-10-13.md。目前 baseline 是空間循跡環境，舊候選不可重複套用；更新 runtime 前仍須確認副本沒有活動訓練。

## 未來純腳本從頭重跑（2026-10-14）

- 使用者確認未來從頭重跑時，從第一階段即使用目前正式空間循跡環境，包括初始化、末端 lookahead v2、有效歷史範圍及依飛機進度更新路段；這些處理也適用於無風，不等到有風階段才啟用。六階段共用一致任務規則，階段之間沿用同一 agent。
- 未來另建新 run、初始化新 agent，固定並記錄環境版本，從第一階段驗證；既有31600評估不代表從頭收斂。沿用目前方案合格後再整理純腳本的安排。本次只記錄，未授權實作、啟動訓練或 commit/push。詳細決定見 docs/records/from-scratch-training-decision-2026-10-14.md。

## 環境版本與遠端保存（2026-10-15）

- 使用者授權實作環境版本架構，並確認遠端已停止或暫停。新 run 從 environments/ 選環境，保存 environment.json 與 environment/ 資產；retry 續訓與 attempt 必須驗證快照 SHA，不再隱式跟隨共用 SLX。
- progressive_v2 使用 schema 2、environment=spatial_v1；目前仍是正式空間循跡與原 reward，未部署離線 reward v2 候選。schema 1 課程仍相容，未綁定環境的舊 run 續訓拒絕猜測。
- 遠端更新前先單獨複製 preserve_training_environment.ps1，對停止且可取得排他鎖的舊 run 保存當地 runtime SLX／相依資產、核對預期 SHA；不搬移 run、不改 checkpoint／課程／guard。保存當下檔案不證明歷史版本；勿先更新後再冒充舊環境。
- 已綁定 run 的評估及恢復分支使用快照；明確跨環境恢復尚未提供，配方 SHA 不符時拒絕。未綁定舊 run 的唯讀評估仍可使用當下 runtime，報告會標明不是歷史環境證據。
- 共用引擎與 MATLAB／工具箱未整體封存，每次 attempt 記錄預檢的模型／引擎 SHA。正式 runtime SLX 保留相容且內容未改。操作與限制見 docs/guides/environment-versions.md。
- 本機已通過 schema、start=false、假引擎、既有課程／恢復 guard、PowerShell 停止／鎖／雜湊／不可覆寫測試及 CPU 五步快照評估；未啟動正式訓練、未驗證遠端 GPU／多 workers、未 commit/push 或直接更新遠端。
- 使用者後續明確授權提交與推送本次課程、reward 校準及環境管理修改。遠端操作由代理提供指令、使用者自行執行；不要自行連線修改遠端或啟動遠端訓練。保存環境必須先於更新程式。
