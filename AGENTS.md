# 專案工作規則

## 先讀與紀錄

- 最新狀態、待辦與成果入口：[docs/records/current-status.md](docs/records/current-status.md)。歷史交接原文完整保存在 [project-history-through-2026-10-19.md](docs/records/project-history-through-2026-10-19.md)；處理相關舊實驗前須讀相應段落及操作文件，不把歷史「未實作」當成現況。
- 重要決策更新current-status；驗證、證據與限制寫入docs/records或research。聊天室不會自動完整彙入日誌；不能宣稱已核對未讀的其他聊天室。

## 授權與資料保護

- 2026-10-19 使用者補充：後續本專案已授權範圍內的修改，代理完成檢查後可自行 commit/push，不必再交由使用者手動 push。仍排除模型、ZIP、完整日誌及無關簡報修改；不包含自行連線遠端或啟動訓練。

- 不擅自啟動／終止訓練；修改runtime、+trainingcurriculum等執行程式前，須確認該副本沒有活動訓練。遠端由代理提供指令、使用者執行，不自行連線更新或啟動。
- 2026-10-20 第三組已正常保存至17200並paused。Custom停止條件已改為建構rlTrainingOptions時同時傳入criteria與回呼；R2024b實測「先向AverageReward options寫回呼」會報型別錯誤，原待辦順序撤回。修改runtime前仍須確認該副本沒有活動訓練。
- 使用者2026-10-20授權本機有上限的候選演算法／飛行測試及整理；不是無限訓練授權。新增SAC是獨立新agent，不能把PPO checkpoint轉成SAC接續。遠端仍由使用者執行。
- 使用者已授權本次程式、文件、連續模式及兩端整理工具commit/push；不包含把模型、ZIP、完整日誌或無關簡報修改加入Git。後續工作依當次使用者授權範圍執行。
- 不重寫已有run的環境、課程、階段、checkpoint或guard快照，不刪狀態解鎖。恢復另建子run、保留來源SHA與lineage；既有pause鎖保持。不得在兩份副本同時續訓。
- 本專案從Flower複製後獨立維護，不依賴來源路徑；使用者授權讀取D:\daniel\GradSchool\0-Beginner\Paper\Flower，未授權修改來源。
- 路徑從專案／程式位置推導；跨機control中的舊絕對路徑需核對。禁止把相對路徑直接交Java canonicalize而解析到System32。

## 結構與同步

- 2026-10-22 使用者交件慣例：通常將待分析檔案放在本機專案根目錄；告知放好後，代理直接查找與讀取，無須再要求上傳。分析後一併歸檔，由代理依用途選擇位置；外來日誌、CSV、評估JSON、ZIP與截圖優先放 artifacts/incoming/<英文任務名或日期>/，摘要寫 docs/records。搬移前確認檔案身分、來源與目的地，保留來源路徑及SHA256紀錄，搬後核驗；不覆寫同名檔，不搬活動run、專案入口或無關檔案，不改寫報告內遠端來源路徑。告知歸檔位置；歸檔不代表已Git同步或可直接續訓。

- 根目錄retry.m為入口；+trainingmodels/為模型，runtime/為引擎，environments/為版本環境，experiments/<課程>/runs/<實驗>/為課程實驗。舊sessions及模型runs保留相容性；不為整理搬移run。
- Git同步程式、JSON、文件與指定精簡report.json；MAT、完整日誌、快取遵守.gitignore。成果透過training_artifacts.py及GitHub Draft Release同步至artifacts/results，驗證SHA；這是評估封存，不是可直接retry的完整run。
- 日常 MATLAB 入口留根目錄；Python／PowerShell 工具在 tools/，MATLAB 準備與稽核在 +trainingtools/，均依自身位置推導專案 root。歷史根目錄指令依 tools/README.md 對照新入口。整理規則見docs/guides/workspace-layout.md；diagnostic_packages含分析腳本，不當成可刪快取。保留使用者未提交檔案。

## 課程、環境與評估語義

- 使用者已更正先前學長規則：訓練時保留 isDone 終止 episode；另外的 Simulink 連續飛行模擬副本不因 isDone／偏差超標而停止。此需求已確認不是實體飛機部署。訓練環境、標準評估與既有 run 快照保留原終止語意；連續模擬結果不能當成原門檻評估過關。先前「非訓練接 Stop Simulation」的說法已撤回。
- 新增資料夾名稱一律用英文；使用者要求透過 groups 分層查找實驗，不為整理搬動活動 run 或改寫既有快照。

- 階段之間沿用同一agent；課程模型定義在JSON最外層。新一輪從頭驗證才初始化新agent；不混用兩者。
- all/any、區間、最低回合與連續達標條件以run課程快照為準，在checkpoint保存邊界正式判定。即時日誌僅暫算，缺資料不猜測；不另傳targetReward覆蓋課程。
- 原配方預算／退步暫停保持。只有明確continuous_training=true的新分支設on_limit=continue、budget_enabled=false、regression_action=monitor；不等於自動LR、回滾、選分支或收斂保證。
- run環境依environment.json及資產SHA驗證，不隱式跟隨共用SLX。未綁定舊run不得猜測歷史環境；跨環境恢復依工具明確支援，不修改快照繞過檢查。
- 目前progressive_v2選spatial_v2：空間循跡，從第一階段使用初始化、末端lookahead、有效歷史與依進度更新路段。不是按原時序追蹤移動目標；3000步不等於完成整條路線。baseline含義依run快照，候選修正不得重複套用。
- 不混合不同環境／reward的分數作純學習改善證據。觀測7為guidance d/30；獨立有限原路線距離另算，初始50m與後段最大值分開報告。IsDone與閾值一致不代表已證明物理根因。
- compare_training_checkpoints是CPU純sim；探索選項只改記憶體agent，不覆寫checkpoint。已內建0.5探索倍率的模型評估用explorationStdScale=1，避免重複減半。不同MAT雜湊不直接等於不同可學權重；公開選項相同不證明optimizer私有狀態保留。
- 同seed配對不等於獨立噪音時序，固定路徑多seed不等於多條路線。訓練過關、凍結評估通過與從頭收斂分開表述；不得放寬終止門檻來假裝修復。
- Worker可在[minWorkers,workers]範圍同attempt使用實際n個，fallback上限不得低於minWorkers；不是保留失敗pool部分連線。learning_health預設只診斷，不冒稱自動介入。
- 畫圖lineage按parent_episode裁切祖先；缺來源／重名／循環提示，不補造歷史。MATLAB singleton JSON object與array均需相容。當前程式SHA不是歷史執行版本證明。

## 目前接續邊界

- 2026-10-21 夜間授權：SAC run `20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b` 已正常保存至1000且paused。使用者授權遠端夜間連續接續；仍由使用者執行，不由代理連線啟動。採同run、serial CPU、每attempt500、checkpoint100、maxAttempts=0，保留原課程／預算／錯誤停止條件；不等同continuous_training分支，不關閉guard或改寫快照。
- 使用者偏好在 MATLAB 查看 `training_status(sacDir,50)`；先以 `artifacts/sac-serial-500-run.txt` 收據取得當前SAC路徑，不只依工作區殘留變數猜測。
- 使用者偏好 PowerShell 即時圖：`python .\tools\plot_training_rewards.py "$session" --watch 6 --view`。優先由同一SAC收據取得session並核對model／environment，勿套用progressive_v2最新run的舊搜尋範例而畫到PPO。腳本已移至tools，不使用根目錄plot_training_rewards.py。提供可直接貼上的遠端指令，含正常暫停方式。

- 目標run 20261017_071436_recovery_tp323769ed已39300回合完成；80次無探索與50次探索皆跑滿，模型權重比對及來源見current-status。Stage8 seed902仍有47.59m後段偏離，不能稱全面穩健。
- 第三組PPO已在17200正常paused，優先用trainingtools.review_round3做16000／17200配對診斷。使用者更正遠端尚未同步完整編排，依docs/guides/round3-next-steps-2026-10-20.md同步；不要重建或重啟第三組。
- 新配方每attempt最多1000、每100回合checkpoint；callback可在達標／guard邊界正常結束段落，保存後才正式判定。500／1000為上限，過關／預算可提早結束。既有run control不自動改寫。shadow_learning_review只出建議，未實作自動LR／選分支；18500是歷史配方。
- 測試依改動範圍執行；合成／假引擎通過不冒稱GPU、多workers或長期收斂已驗證。不得因測試需求擅自啟動正式訓練。
