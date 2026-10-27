# 目前狀態與接續入口

更新：2026-10-27。這是專案狀態摘要，不是遠端即時監控或所有聊天室的逐字備份。

## 已完成

- 2026-10-27 MLP低LR子run20261027_015231_recovery_tpbbe84468正常v7保存至2500，guard suspected_regression paused。完整日誌新增400回合／290091步，前82次全跑滿，2183起崩落，最後300次無滿長；低actor LR未防止本輪退步。舊actor-pair收據再次歸檔，非本輪來源。下一步僅child2500關探索凍結評估並收recovery／計時資料，不解鎖retry或繼續盲調。[結果](sac-mlp-slow-result-2026-10-27.md)。

- 2026-10-27 遠端2100 v7獨立probe已核對passed／來源SHA一致／optimizer-replay-weights-history統計保留。新增每run明確checkpoint_storage.json，舊run缺設定仍v7.3；低LR新分支配方選v7，準備、週期、初始及段末保存一致。本機兩短回合跨程序保存續載、v7檔頭及5步凍結評估通過；不證明長期收斂或根治原生當機。下一步pull後重新建立全新2100低LR分支並retry最多500（至2600），保留原paused及失敗.preparing。[驗證與限制](sac-v7-storage-2026-10-27.md)。

- 2026-10-27 遠端低LR分支準備當機、尚未retry；ZIP兩份原生dump分別為HDF5讀取存取違規與寫入abort/assert。未完成.preparing只有約67MB暫存checkpoint，保留不發布。新增獨立probe_sac_v7_save診斷替代格式，不改正式保存流程／來源；下一步先遠端2100單次保存讀回核對，暫停先前retry指令。不能由stack直接認定RAM不足或已修復。[證據與限制](sac-hdf5-crash-2026-10-27.md)。

- 2026-10-27 三份MLP凍結報告已收、complete且weights_unchanged：2100／2300／2500關探索分別3000／120／3000步，後10秒原路線最大偏差3.488／50.065／17.945m。選2100作新子run來源，原run保持paused。新增actor1e-5（原5e-5）有界500回合配方，serialCPU、checkpoint100、maxAttempts1、guard退步pause／預算啟用；不改課程門檻，不保證根因修復。MLP兩回合fixture準備／保存載入驗證通過，未啟動訓練。下一步使用者核來源SHA後prepare並retry，最高2600，可提早停止。[證據、限制與執行規格](sac-mlp-frozen-next-2026-10-27.md)。

- 2026-10-27 MLP長跑child的2100單checkpoint凍結評估完成：Stage1 seed101關探索，reward2839.49、3000步、step_limit、environment_done=false；已讀使用者diary並核SHA歸檔artifacts/incoming/sac-mlp-frozen-2100-20261027。尚未收到evaluation.json及trace，不能報獨立路線距離或多seed穩健。先前MATLAB關閉原因未明，沒有crash report可定位；單次成功不證明記憶體或評估器問題已修復。下一步先分別單checkpoint跑2300／2500關探索，打包三份完整報告，再決定探索測試；保持訓練paused，不重跑已完成2100。[補充紀錄](sac-mlp-2500-2026-10-26.md)。

- 2026-10-26 MLP連續子run `20261026_203618_recovery_tp18ecff57` 已由使用者確認attempt3正常保存2500且maxAttempts paused；使用者要求停止，保持暫停。已讀完整2001–2500日誌：2200窗平均1884但窗末137步，2500窗平均917且末24次全3000步，不能以移動平均替代凍結評估。下一步2100／2300／2500 seed101有無探索共6次純sim，暫不續訓或改課程。根目錄兩份交件已核SHA歸檔，actor pair收據仍屬舊recurrent。下列1000與「未遠端實跑」為先前歷史，已由本次長跑回報更新。[分析與限制](sac-mlp-2500-2026-10-26.md)。

- 2026-10-26 使用者回報新MLP run `20261026_184028_tpcff39fc6_3ef5_4435_bfaa_cfffd7ebc83f` 已正常 paused於Episode1000/2000；最新100回合reward158.94、steps263.64、滿3000步率0%，離原條件尚遠。`mlp_stdout.log`尾端確認正常保存、無通關。已新增從Agent1000建立獨立連續SAC子run的100k新增回合配方：每段500、每100保存、200段上限，原成功門檻保留、guard退步只監看；父run與快照不改，未啟動訓練。因SAC連續恢復原由helper拒絕，準備工具已放行不調探索倍率的SAC連續子run；此路徑尚未遠端實跑驗證。[分析與可貼指令、交件SHA](../guides/sac-mlp-continuous-100k-2026-10-26.md)。

- 2026-10-26 新MLP run20261026_184028_tpcff39fc6_3ef5_4435_bfaa_cfffd7ebc83f完成500／82258步並maxAttempts正常paused；五個百回合reward約98–103，無跑滿，尚無明顯改善。使用者另交actor pair收據屬舊recurrent分支，不用於此run。日誌／兩份狀態已歸檔。下一步先Agent500 seed101有無探索凍結基準兩次，再同run不改參數續一段最多500至1000，保留guard及總2000上限。[分析](sac-mlp-500-2026-10-26.md)。

- 2026-10-26 已準備獨立從頭sac_mlp128前饋試驗，Stage1-only課程sac_mlp_stage1_v1；保留直線／無風／reward／isDone／原門檻，總預算2000、先500、checkpoint100、serialCPU。架構與SequenceLength1一起變，非等計算量LSTM因果驗證，無收斂保證。64步合成學習及原recurrent建構回歸通過；本機兩真實回合242/148步保存接續與5步凍結評估通過。舊run不變；下一步使用者遠端prepare_sac_mlp_trial後只開第一段。[驗證](sac-mlp-preparation-2026-10-26.md)、[指令](../guides/sac-mlp-stage1-2026-10-26.md)。

- 2026-10-26 actor兩組2100凍結評估已收：低LR候選有無探索6次全3000步，但後10秒原路線偏離6.65–7.18m，劣於父1600約0.98–1.38m；原LR對照全110–111步distance_threshold。兩組paused／exit0；實際耗時4h28m17.5s與5h33m56.4s，含啟停吞吐約32.34／32.29步秒。建議封存此輪、不再盲目接續；同配方重開可能重複問題，新從頭實驗需版本化變因與有界穩定性評估。未新增課程或啟動。[最終結果與重開判斷](sac-actor-final-evaluation-2026-10-26.md)。

- 2026-10-26 原LR對照20261025_235136_recovery_tpb9f03642已正常保存2100，guard suspected_regression；新增500回合／520648步，最後300回合無跑滿。與低LR候選比較，首次短回合1733對1723，尚無延後退步證據；候選末32回合恢復，但多24.25%互動步數，不能宣稱因果優勢。pair收據確認同1600來源SHA；根目錄三份交件已歸檔。下一步兩組2100有／無探索凍結評估共12次，先不續訓或調參。[結果與下一步](sac-actor-pair-result-2026-10-26.md)。

- 2026-10-26 actor LR候選20261025_235817_recovery_tpd681ba86已正常保存2100、guard suspected_regression後paused。新增500回合／646929步，最初122次全跑滿，1801–2000無跑滿，末32次又全跑滿；最後100 reward1081.40／跑滿34%，不能當最後凍結模型成績。2358stdout及狀態已歸檔。下一步只啟動既有原LR對照child一段500，候選不解鎖不續訓；未證明LR改善或課程根因。[分析](sac-actor-pilot-result-2026-10-26.md)。

- 2026-10-25 共用序列結果已收：兩段各256步、五checkpoint SHA一致，100k1400 actor分布明顯偏離；500k1600失敗但良好輸入雙Q仍接近，非critic健康證明。準備下一個有界actor LR試驗：從100k1600良好checkpoint建立原LR5e-5對照／LR1e-5候選，僅候選由使用者啟動，serial CPU、每段500、maxAttempts1、總新增500，課程及guard保持。新增R2024b序列化LR修改以保留optimizer歷史；未啟動遠端。[證據與設計](sac-actor-pilot-2026-10-25.md)。

- 2026-10-25 使用者授權繼續診斷及必要課程修改；本次先新增probe_sac_replay_pair，兩組1600各取一段terminal分界後的episode前綴（最多256步），五checkpoint共用相同資料、逐步更新LSTM，輸出Gaussian mean/std與歷史action的雙Q。零初始state、前64步warm-up，非TD誤差或新飛行測試；保留課程及run快照。遠端下一步唯讀推論後回傳ZIP。[範圍與指令](sac-shared-sequence-probe-2026-10-25.md)。

- 2026-10-25 SAC內部診斷ZIP已核對：五checkpoint SHA與既有證據一致、policy state／optimizer欄位齊全，網路與近期reward無NaN/Inf。alpha依序0.01679／0.00531／0.00967／0.00376／0.00422，500k1400更低alpha仍成功，不能判定entropy係數偏低為根因；近期10000筆terminal markers為4／46／4／4／90，不等於失敗率或完整buffer分布。critic-target參數差非Q誤差。已歸檔artifacts/incoming/sac-state-review-20261025；保留兩組良好checkpoint及paused，未改參數。後續機制診斷須同序列actor分布／Q與TD行為。[分析](sac-state-review-2026-10-25.md)。

- 2026-10-25 新增R2024b SAC唯讀checkpoint診斷入口inspect_sac_replay_pair：來源1100及兩子run1400/1600依序讀取，檢查paused與排他鎖、前後MAT SHA；輸出entropy係數、網路／target參數摘要、optimizer保存旗標及最近最多10000筆replay統計。無訓練／sim／參數改寫，不冒稱可恢復歷史loss或已定位根因。下一步使用者遠端執行並回傳五份JSON的ZIP。[指令與驗證範圍](sac-snapshot-diagnostics-2026-10-25.md)。

- 2026-10-25 收到SAC replay配對凍結評估RAR：四份complete／weights_unchanged=true、共24次，環境／課程／runtime及同分支checkpoint SHA一致。100k1400僅85–88步、1600有無探索皆3000步（後10秒原路線最大偏離0.984／1.120–1.381m）；500k1400皆3000步、1600僅195–219步，關閉探索仍失敗。擴buffer未消除策略退步，尚不能定位課程／LR／entropy根因；保留100k1600作Stage1參考，兩run保持paused。RAR已核SHA歸檔artifacts/incoming/sac-frozen-pair-20261025。下一開發重點為有限checkpoint內部診斷，非直接開新課程訓練。[完整核對](sac-frozen-pair-2026-10-25.md)。

- 2026-10-25 SAC500k候選正常保存1600並paused；新增500回合／1053075步，1301–1400全跑滿，最新100 reward76.55／steps127.83／跑滿0%。比100k對照多40.33%互動步數，不能視為等步數因果比較；擴buffer未消除退步。根目錄7份交件檔已按來源移至artifacts/incoming/root-intake-20261025並核SHA，無根目錄PNG，附件截圖另複製歸檔。SAC現有課程確實沿用PPO階段／門檻；建議另版SAC步數預算、凍結評估與replay-aware升階流程，但第一階段內崩落未證明是課程所致，未改快照或門檻。下一步兩分支1400/1600配對凍結評估。[詳細分析與提案](sac-buffer-comparison-2026-10-25.md)。

- 2026-10-24 SAC100k對照組已依使用者狀態正常保存至1600並paused，新增500回合／750422步，最新100 reward927.11、跑滿32%，最後9回合跑滿但仍反覆退步。1024_stdout.log已核對歸檔artifacts/incoming/sac-baseline-1600-20261024。下一步僅由使用者啟動既有500k候選20261023_204044_recovery_tp6038f3af一段最多500回合，其餘run保持paused；不宣稱等步數公平比較已完成。[分析](sac-baseline-1600-2026-10-24.md)。

- 2026-10-23 遠端修正後配對準備成功：pair.json已核對並歸檔artifacts/incoming/sac-replay-pair-20261023；來源1100 SHA bc7ae929a634044b0c0b5002ece80376ffe00f1a0a411d0d0f22cc0972fc74dd與既有評估一致。新baseline為20261023_203402_recovery_tp85477afc，500k候選為20261023_204044_recovery_tp6038f3af，均prepared_only（依收據及使用者終端回報，未獨立讀遠端）。下一步使用者只啟動baseline一個attempt、最多新增500回合至1600；保留guard與原run暫停，候選不並跑。這是首段試跑，不冒稱兩組已具有相同環境步數預算。

- 2026-10-23 SAC replay修正：遠端僅完成baseline子run20261022_132700_recovery_tp4c73786a，candidate因Replay data changed中止，未開訓。已用128容量／173筆循環覆寫重現舊檢查失敗：R2024b擴容將實體ring位置轉為時間順序。修正為嚴格比對時間順序與tracker IDs，不清buffer或放寬內容比較；保留既有基線，遠端更新後重新準備一對新子run。[根因與驗證](sac-replay-ring-fix-2026-10-23.md)。

- 2026-10-22 SAC對照準備工具：已支援從同一SAC checkpoint建立100k／500k replay子run，透過R2024b序列化狀態重建避免直接改AgentOptions重設optimizer；核對權重、target、optimizer、entropy policy state與replay。合成64步與真實兩回合fixture分支準備通過，無遠端訓練啟動。遠端下一步僅從1100準備兩子run並回傳receipt；非等步數比較已完成，也非收斂保證。[驗證](sac-replay-preparation-2026-10-22.md)、[遠端指令](../guides/sac-replay-pair-2026-10-22.md)。使用者「繼續直到可執行下一步」偏好已寫AGENTS。

- 2026-10-22 最後段log已核對歸檔：attempt4完整1501–2000，628069步／19237.1秒=32.65步每秒（含啟停保存）。1994雖跑滿但reward已降1185.73，1995–2000僅667/228/226/259/241/292步，最後6回合平均166.21；最後100均值2622.19掩蓋近期崩落。可解釋Agent2000凍結失敗，並非僅評估／重啟才出問題。來源與SHA見[SAC配對分析](sac-paired-review-2026-10-22.md)；檔案已移artifacts/incoming/sac-review-2000-20261022，原run維持paused，未改參數。

- 2026-10-22 SAC配對評估已收到：兩份12:44交件JSON皆complete、各12次、weights_unchanged=true，環境／課程／四個checkpoint SHA一致。1100與1300有無探索均跑滿；1500無探索95步、有探索95–96步；2000無探索142步、有探索144–145步，皆有distance_threshold證據。不是單純探索造成退步；1100後段原路線最大偏離2.63m，1300已26.08m（無探索）。兩份報告已核驗SHA並移至artifacts/incoming/sac-review-2000-20261022；根目錄交件後代歸檔偏好已寫AGENTS。原run維持paused，未續訓。[完整分析](sac-paired-review-2026-10-22.md)。

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

最新優先：使用者同步最新程式後，依[MLP長跑指令](../guides/sac-mlp-continuous-100k-2026-10-26.md)從 paused Agent1000 準備獨立子run；檢視lineage與快照後，再由使用者明確啟動。最大100000新增回合，原課程成功條件仍可提早結束；未驗證前不得宣稱此長跑路徑已實跑成功。

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
