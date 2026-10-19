# 專案工作規則

## 先讀與紀錄

- 最新狀態、待辦與成果入口：[docs/records/current-status.md](docs/records/current-status.md)。歷史交接原文完整保存在 [project-history-through-2026-10-19.md](docs/records/project-history-through-2026-10-19.md)；處理相關舊實驗前須讀相應段落及操作文件，不把歷史「未實作」當成現況。
- 重要決策更新current-status；驗證、證據與限制寫入docs/records或research。聊天室不會自動完整彙入日誌；不能宣稱已核對未讀的其他聊天室。

## 授權與資料保護

- 2026-10-19 使用者補充：後續本專案已授權範圍內的修改，代理完成檢查後可自行 commit/push，不必再交由使用者手動 push。仍排除模型、ZIP、完整日誌及無關簡報修改；不包含自行連線遠端或啟動訓練。

- 不擅自啟動／終止訓練；修改runtime、+trainingcurriculum等執行程式前，須確認該副本沒有活動訓練。遠端由代理提供指令、使用者執行，不自行連線更新或啟動。
- 使用者已授權本次程式、文件、連續模式及兩端整理工具commit/push；不包含把模型、ZIP、完整日誌或無關簡報修改加入Git。後續工作依當次使用者授權範圍執行。
- 不重寫已有run的環境、課程、階段、checkpoint或guard快照，不刪狀態解鎖。恢復另建子run、保留來源SHA與lineage；既有pause鎖保持。不得在兩份副本同時續訓。
- 本專案從Flower複製後獨立維護，不依賴來源路徑；使用者授權讀取D:\daniel\GradSchool\0-Beginner\Paper\Flower，未授權修改來源。
- 路徑從專案／程式位置推導；跨機control中的舊絕對路徑需核對。禁止把相對路徑直接交Java canonicalize而解析到System32。

## 結構與同步

- 根目錄retry.m為入口；+trainingmodels/為模型，runtime/為引擎，environments/為版本環境，experiments/<課程>/runs/<實驗>/為課程實驗。舊sessions及模型runs保留相容性；不為整理搬移run。
- Git同步程式、JSON、文件與指定精簡report.json；MAT、完整日誌、快取遵守.gitignore。成果透過training_artifacts.py及GitHub Draft Release同步至artifacts/results，驗證SHA；這是評估封存，不是可直接retry的完整run。
- 日常 MATLAB 入口留根目錄；Python／PowerShell 工具在 tools/，MATLAB 準備與稽核在 +trainingtools/，均依自身位置推導專案 root。歷史根目錄指令依 tools/README.md 對照新入口。整理規則見docs/guides/workspace-layout.md；diagnostic_packages含分析腳本，不當成可刪快取。保留使用者未提交檔案。

## 課程、環境與評估語義

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

- 目標run 20261017_071436_recovery_tp323769ed已39300回合完成；80次無探索與50次探索皆跑滿，模型權重比對及來源見current-status。Stage8 seed902仍有47.59m後段偏離，不能稱全面穩健。
- 進度可觀察性已實作，無須重做舊待辦。第三組新agent、八階段、固定spatial_v2的 preflight 已實作於 trainingtools.preflight_round3；先完成使用者 push／遠端 pull，再建立並核對新 run，尚未啟動正式run。JSON自動決策仍是提案；不要把18500歷史恢復配方當成下一輪指令。
- 測試依改動範圍執行；合成／假引擎通過不冒稱GPU、多workers或長期收斂已驗證。不得因測試需求擅自啟動正式訓練。
