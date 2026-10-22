# 目前狀態與接續入口

更新：2026-10-21。這是專案狀態摘要，不是遠端即時監控或所有聊天室的逐字備份。

## 已完成

- 2026-10-22 遠端使用者回報：新SAC run於11:23:53+08:00以maximum attempts正常paused，attempt4，checkpoint已列至Agent2000；四段ExitCode皆0、ActualWorkers皆0（serial）。耗時1602.1／6884.6／24118.4／19237.1秒；前3段依CSV步數算整段吞吐46.29／37.80／35.69步每秒，含啟停保存，不能當純sim速度。第4段完整步數尚缺。下一步以1100／1300／1500／2000、Stage1、seed101/102/103做有／無探索凍結配對，最多24次3000步；尚未執行。已核對本機R2024b SAC UseExplorationPolicy開關會同步反向UseDeterministicExploitation，不調低探索倍率。

- 2026-10-22 段末暫停指令修正：使用者遠端 File.Replace 的第三參數傳 $null 報不合法路徑，不能視為暫停設定成功。指南改用明確唯一備份路徑並讀回 maxAttempts 核對；本機獨立暫存檔替換驗證通過（新值1、備份舊值0），未操作訓練檔案。遠端仍須使用者重試並回報。

- 2026-10-22 SAC參數對照：根目錄reward_history.csv共1905個連續回合；1001–1100全跑滿，1321起於attempt3內明顯退步，1401–1600無跑滿，最新100回合reward1707.45／跑滿56%。已查SB3、Spinning Up與RL Zoo原始設定，對照本機R2024b與目前配方；buffer容量與更新比例列為待驗證假說，非已確診根因。先建議高低checkpoint凍結配對與entropy／loss診斷，再做單因素子run。未改執行程式或啟停訓練。[證據與參數對照](sac-parameter-review-2026-10-22.md)。

- 2026-10-21 夜間接續：使用者提供新組stdout_new.log，完整501–1000回合，最後956–1000連續45次跑滿；最新100回合reward1544.85／steps1878.95／跑滿51%。trailing2558.0822已核實為最後50回合，非100回合口徑。500回合皆有Fast Restart不支援無上限變長訊號的警告；新增可選fastRestart=off，未改SLX／LR／門檻。使用者授權同run夜間自動接段，maxAttempts=0、每段500、checkpoint100，保留原課程與錯誤停止條件；偏好training_status(sacDir,50)與tools即時曲線已寫AGENTS。[分析](sac-overnight-review-2026-10-21.md)、[夜間指令](../guides/sac-overnight-2026-10-21.md)。

- 2026-10-21 新組方案：使用者已選單程序CPU SAC、每attempt最多500、每100checkpoint、先1attempt。已加入顯式serial執行與R2024b裝置恢復、新agent保存PolicyState；本機CPU/GPU合成恢復與兩回合真實serial飛行（108／124步）、跨段保存及5步凍結評估通過。這不是長期收斂／速度保證。遠端舊組尚未paused時不要pull或啟動新組。[交付驗證](sac-serial-delivery-2026-10-21.md)、[完整遠端指令](../guides/sac-fresh-serial-2026-10-21.md)。

- 2026-10-21 重要更正：後續真實飛行堆疊確認R2024b預設走新版OffPolicyTrainer，包含parallel路徑亦依LearningFrequency計算epoch。先前舊ExpSyncParallelTrainer／直接replay測試不能證明遠端實際頻率失效，該根因推論撤回。下方早期頻率結論僅描述legacy入口。GPU保存載入轉CPU已獨立重現；使用者已選單程序CPU、每attempt500回合作獨立對照，遠端舊組仍待正常暫停。

- 2026-10-21 使用者授權低RAM本機測試後，單程序CPU/GPU合成probe通過：32步、頻率1/8的serial學習呼叫為25/4，平行trainer使用的直接replay入口皆32次；未開pool。另重現GPU agent保存載入後actor／雙critic皆cpu，權重與replay長度保留；專案resume未重新套用device，提供遠端低GPU使用率的具體候選機制。尚未檢查遠端記憶體agent或修正runtime，不代表GPU必更快或收斂已修好。見[本機測試](sac-local-probe-2026-10-21.md)。

- 2026-10-21 SAC唯讀程式稽核：引擎CRLF SHA與遠端attempt3完全吻合。本機R2024b同步平行SAC逐experience直接呼叫replay learning，未經LearningFrequency=32的串行頻率gate；可解釋主程序長時間忙碌的候選機制，不宣稱遠端toolbox逐檔一致／32倍加速／退步根因。官方R2024b另標示recurrent parallel不支援，需保留支援性限制。GPU續載狀態、重複載入與保存成本仍需量測。見[程式稽核](sac-code-review-2026-10-21.md)。未改runtime或啟停訓練。

- 2026-10-21 使用者補充GPU與CPU採樣：GTX1660約42秒GPU使用率0–3%；另一次10秒CPU採樣，對照attempt3程序樹確認主MATLAB PID22304為344.8%單核心用量、六個pool子程序各約0.2%。支持優先查主程序工作與等待時間，不證明整段瓶頸或網路在CPU運算。使用者確認仍在等待目前attempt正常結束；不能視為已paused。

- 2026-10-21 後續診斷ZIP已核對：SAC control.maxAttempts=1，採集時仍為attempt3，尚未確認paused。三段均設定gpu且取得6workers；前兩段1000回合分別耗時1h10m26s／10h38m14s，包含啟停與保存的吞吐74.98／39.22步每秒，不能只歸因回合變長，也未定位GPU／模擬／保存瓶頸。最新2150回合，最近100回合reward=694.60、steps=844.73、跑滿率18%。詳見同份[SAC日誌核對](sac-log-review-2026-10-21.md)的ZIP補充；後續索取資料直接提供可貼上指令。

- 2026-10-21 使用者提供 SAC 三份 stdout：run `20261020_201931_tpad1142e4_44c3_4019_a786_72e4faa3b614` 已記錄 1–2144 回合，全為 Stage1。前兩段正常保存；第三段目前程序狀態未知。1313、1787起明顯退步均在同一attempt／階段；2133–2144重新跑滿，但最新100回合均值reward=559.30、steps=702.38、跑滿率12%，未過關。每段取得6workers；無時間戳，不能判定速度瓶頸。詳見[SAC日誌核對](sac-log-review-2026-10-21.md)。下方「尚未收到SAC正式啟動回報」已由本次資料取代；不據此授權額外啟動。

- 2026-10-20使用者貼回第三組四次配對評估：16000無探索1658步／探索1649步，17200無探索1786步／探索530步；全部distance_threshold，獨立路線最大距離約50.26–50.59m。不能只歸因探索噪音，也未證明LR根因。保持paused，下一步取得已生成的兩個report資料夾之traces，不重跑、不直接啟動17200子分支。見[結果與限制](round3-paired-review-2026-10-20.md)。

- 2026-10-20 後續：新增獨立 recurrent SAC 候選（新agent，保留原PPO）、1000回合attempt配方及500／1000回合恢復分支支援。課程／guard在checkpoint頻率邊界請求正常保存並結束段落，不必每100回合重建pool。Custom停止條件改為建構options時一起提供criteria與回呼，修正R2024b中間狀態問題。SAC短訓練、兩回合CPU實際飛行／跨階段接續與凍結評估已通過，不代表收斂或GPU／6workers性能。
- 連續模擬已新增完整入口並完成一次3000步CPU模擬；本例原done=0，沒有證明超標後恢復。shadow歷史重播已完成393個百回合邊界，零動作執行；自動LR／回滾／啟動仍未實作。舊Stage8 seed902已補觀測／原始action證據，物理根因未定。詳見[本次交付與限制](sac-long-attempt-validation-2026-10-20.md)。
- 使用者最新更正：**遠端尚未同步完整檔案編排**。本機整理預覽無可搬項目；groups捷徑在本機因來源run不存在而不建立。新增finish_workspace_layout.ps1，取得paused run排他鎖後執行既有整理工具；遠端按[下一步指令](../guides/round3-next-steps-2026-10-20.md)同步與Apply。舊部分快取整理回報不視為全部同步完成。

- 2026-10-20 15:06（使用者貼回遠端狀態）：第三組 attempt188 正常退出（exit=0），經 control.maxAttempts=1 在下一段啟動前進入 paused，message 為 Configured maximum attempts reached; checkpoints retained。training_status 顯示保存決策至 17,200、Stage3 共 9,300 回合、conditions_not_met，日誌明示 Training stopped normally / Saved in。最新 stdout 100 回合估計 reward=1267.42、steps=1603.81、跑滿率0%；末行 trailing mean=1122.7171 的統計口徑尚未核實，不混用。保留 maxAttempts=1 與原 run，未指示重新啟動；尚未獨立檢查遠端程序退出或 MAT 可讀性。

- 2026-10-20 使用者提供第三組 reward_history.csv：已記錄至 17,030 回合，證明該 run 已有正式訓練資料；目前是否仍在執行未核實。依截圖第三階段起點 7,901，後續 9,130 回合沒有一次達到 3,000 步，最高 1,880 步；最新 100 回合平均 reward=838.2661、steps=1162.65。回落伴隨步數縮短，根因未定。見[CSV 診斷與限制](round3-reward-history-2026-10-20.md)。下方「尚未收到啟動結果」為先前紀錄，已由本次資料更新。

- 使用者已更正 isDone 規則，並確認需求是 Simulink 連續模擬、不是實機。新增 simulations/continuous_flight/FAFA_ContinuousFlight.slx：RL Agent done 固定 false，原 done 保留紀錄，StopTime=300；原 spatial_v2 SHA 不變，21 個嵌入程式相同，結構測試通過但未做完整飛行 sim。新增英文 groups/group_02_recovery 與 group_03_fresh 查找層級；捷徑工具不搬動任何原始 run。詳見 [本次驗證與限制](continuous-flight-and-groups-2026-10-19.md)。

- 先前「非訓練時 isdone 接 Stop Simulation」的說法已由使用者更正撤回，以上方連續模擬規則為準。原始唯讀接線證據仍成立：spatial_v2 的 isdone（SID362）接至 RL Agent（SID445）第3輸入；compare_training_checkpoints 使用 rlSimulinkEnv 與 sim(env,agent,...)。標準訓練／評估保持此接線，不能把連續模擬模式當原門檻驗收。

- 使用者貼回第三組正式準備結果：experiments/progressive_v2/runs/20261019_164959_tpc77cb232_0370_4212_a632_e1644201eec0，遠端根目錄 D:\daniel\ModularTraining。以 start=false 新建，spatial_v2 的 run 快照 ID 與 SHA 斷言通過，診斷目錄在該 run/diagnostics。這是新 agent 從頭訓練的獨立 run，尚未收到 Supervisor PID／啟動結果；後續只對此 run 啟動，不再次執行建立新 run 的 retry(args{:})。

- 使用者後續貼回：實驗室 compact Apply 完成 2 個根快取檔的搬移與雜湊驗證（receipt：artifacts/incoming/layout-20261019-164754-6f8532bb）；第三組 preflight 通過，ppo_lstm128、八階段、spatial_v2，runCreated=0、trainingStarted=0。遠端課程 SHA 7bfc6c733c369ad8f6c29111cabd0b20f6f618afbd3e4f8a2e9c2aea37edebfc 與本機同檔轉 CRLF 的 SHA 完全一致；本機 LF 為 6dc1ee14695C3E210A4F1E215A56DF0890FC0F8D10BC61BDA52FC676C9ACF3E6。環境 SHA 仍為 997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557。尚未收到第三組正式 run-id 或啟動結果。

- 使用者貼回實驗室輸出，確認已 fast-forward 至 7ded2ea。compact_workspace 僅預覽根目錄 2 個 Python 快取檔，尚未 Apply；未收到第三組 MATLAB preflight 結果。使用者已授權後續已授權修改由代理自行 commit/push，詳見 AGENTS。

- 根目錄縮編完成：19 個工具移至 tools/ 與 +trainingtools/，呼叫與根目錄定位已更新；簡報建置資料／根快取 118 檔已搬移核驗、12 份腳本保留原稿後調整路徑。43 項 Python、5 組 PowerShell、6 組 MATLAB 檢查通過；其中一組包含合成 CPU PPO 兩回合，無正式飛行訓練。詳細證據、資料保護與限制見 [重構紀錄](layout-refactor-2026-10-19.md)。本次由使用者後續 push；遠端未更新本次重構。
- 第三組開訓前入口 trainingtools.preflight_round3 已通過本機核對，固定八階段 progressive_v2／spatial_v2，從新 agent 開始；沒有建立正式第三組 run。依 [第三組準備](../guides/round3-fresh-training.md) 先同步與核對，再建立新 run、另行啟動。

- 2026-10-19 後續整理：根 README、文件入口、課程首頁與完成模型卡串接；workspace-layout 補完整目錄分工、遠端 main 的 pull 指令及驗證後複製模型步驟。整理工具預覽回報 Nothing to organize，沒有搬動 run。PowerShell 核對上述 Markdown 本機連結、模型 SHA256、Git 白名單與 MAT／日誌／未知 JSON 排除均通過；git diff --check 通過。Python 系統別名不可執行，故用 PowerShell 完成檢查，未執行 MATLAB 或訓練。簡報與 ZIP 的使用者變更排除於本次提交。

- 課程成果展示入口已加入 [experiments](../../experiments/README.md) 與 [progressive_v2](../../experiments/progressive_v2/README.md)。Git 白名單只放行課程／成果 README 和逐模型 provenance.json，MAT 與完整日誌仍忽略。39300 成果卡保留恢復來源、評估限制及下載指令；未宣稱從頭收斂。未實作自動登錄或完整訓練歷程封裝，未新增曲線。這次僅調整文件與忽略規則，未啟動訓練。

- 依使用者希望從課程內查看完成模型，本機已新增 `experiments/progressive_v2/completed_models/20261017_071436_recovery_tp323769ed/Agent_Success.mat`；從探索評估 Release `e177d217bc1f` 封存複製並核對來源／目的 SHA256 相同，旁附 `provenance.json`，入口有 README。此處僅供完成模型查找與評估，不是完整可續訓 run；原封存與既有 run 未移動。未啟動 MATLAB／訓練，未推定另一台已同步。

- progressive_v2 run `20261017_071436_recovery_tp323769ed`：39300回合、attempt224、conditions_met，使用者確認沒有啟動新run。
- 無探索Stage1–8共80次、探索Stage4–8共50次都跑滿3000步。不是130個獨立情境；[完整驗收與限制](success-evaluation-2026-10-19.md)。
- Agent_Success與Agent39300的actor／critic可學權重及公開AgentOptions一致；optimizer私有狀態未驗證。
- 兩份成果Release已下載到本機並通過SHA256：tag尾碼 `49e0834c5ef8`（無探索）、`e177d217bc1f`（探索）。來源與路徑見驗收紀錄。
- 階段邊界與條件進度顯示已實作；[操作說明](../guides/training-progress-display.md)。連續模式可明確啟用，但不是自動LR控制器；[限制](../guides/continuous-training.md)。

## 下一步

最新優先：等遠端舊SAC正常paused，依[新組指令](../guides/sac-fresh-serial-2026-10-21.md)同步並建立獨立serial CPU／500回合試跑；不直接續訓或改寫舊SAC／PPO。下列1000回合初試建議是先前方案。

2026-10-20後續：已收到根目錄paired-review ZIP，完成四份MAT軌跡唯讀抽取與路線疊圖。16000兩次於左下轉彎附近失敗，17200無探索在左側向北路段、有探索在右側向南路段失敗，並非共同單一彎點。見[軌跡初步核對](round3-paired-review-2026-10-20.md)。建議下一輪獨立SAC限1 attempt／最多1000回合，由使用者遠端執行；不必等待完整PPO因果分析。尚未收到SAC正式啟動回報。

1. 遠端保持第三組paused，依[下一步指令](../guides/round3-next-steps-2026-10-20.md)pull與整理／建立groups捷徑，保留本機未提交檔。若需另一台完整成果模型，再依workspace-layout下載與核對SHA。
2. trainingtools.review_round3四次評估與本機軌跡初步分析已完成；window更新／控制因果仍待驗證。不要把17030 CSV的全區間統計延伸到17200。
3. 下一輪建議獨立SAC新agent試驗；準備工具不啟動。SAC首次啟動限1 attempt、最多1000回合；原PPO保持paused，不同時啟動PPO子分支。
4. [JSON自動決策](../research/autonomous-curriculum-proposal-2026-10-18.md)第一階段shadow已實作；獨立validation／有限自動介入與冪等啟動尚未完成，不能宣稱無人值守調參。
5. Stage8 seed902後段47.59m偏離保留為回歸案例；已補trace證據，仍缺控制／路段因果驗證，不能藉放寬50m門檻宣稱修復。

## 查找紀錄

- [歷史交接原文](project-history-through-2026-10-19.md)：原AGENTS完整封存，內含當時狀態與已失效的待辦描述；勿當作目前狀態。
- [文件索引](../README.md)、[離線可搜尋首頁](../index.html)、[配方分類](../../configs/README.md)。
- 各聊天室沒有自動完整寫入專案；重要新決策需更新本頁，細節另寫records／research並在AGENTS保留必要規則。歷史文獻與結論不改寫成最新結果。
