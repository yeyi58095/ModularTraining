# progressive_v2 起始循跡退步：2026-10-16 離線診斷

來源：使用者提供 regression_detail_20261016_160856.zip。ZIP CRC 檢查通過，包含 evaluation.json、scenarios.mat 與三份 trace；沒有 checkpoint 本體或訓練 attempt 日誌。未做模擬或訓練，未修改 runtime／實驗。

評估來源 run：20261015_141048_tpcd5dc3c7_07cf_4ebb_8c77_b102cf24c18c。報告 complete、CPU、Stage 1 straight_calm、seed 501、無風、凍結策略。使用 run_snapshot spatial_v2，模型 SHA256 997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557；報告 weights_unchanged=true。此為報告證據，本包沒有原 checkpoint 可供本機重新核對其 SHA。

| Checkpoint | 步數 | reward | 觀察 |
|---|---:|---:|---|
|18400|3000|2975.91494|前10秒 guidance d 最大38.78356 m，之後能恢復|
|18500|87|55.65122|8.7秒 d=50.89947 m，提前終止|
|18600|81|45.17112|8.1秒 d=50.54237 m，提前終止|

三者初始 planned_path、window_path 完全相同；前10秒（失敗者取其全部時間）只有 t=0 發出 window_valid，且沒有後續 planned_path/window_path 內容變更。初始化已產生路徑與前方目標。故這三次評估的失敗不是等到中途換 window 才發生，也不是只改 reward 造成的圖表下降。

初始 action 分別 -0.4045、-0.4083、-0.4101；後續閉迴路演化不同。t=4秒 roll 約 -0.2142、-0.3157、-0.5353 rad。18500、18600 的北向偏移持續擴大，終端 P_N 與 guidance d 相符，且 P_E 已位於原直線範圍內，因此不是只有 guidance 距離讀值變大的現象。不能把閉迴路不同時刻的 action 差異當成相同 observation 下的策略差異。

使用者 audit 顯示五個 checkpoint 的主要超參數相同、權重皆 finite；其距離統計均相對17000，不能相減當作18400→18500的更新幅度。initial_snapshot_count=0 不足以證明 resume 正確或錯誤。尚未檢查 optimizer 內部狀態。

結論：已確認被抽樣 checkpoint 的起始循跡能力在18400與18500之間惡化；18400也有明顯起始擺動，不能視為完全穩健或全歷史最佳。尚無證據確定學習率、PPO更新、LSTM狀態或重啟為根因。下一步需相鄰 checkpoint 本體及18401–18500相關訓練／啟動日誌，做相同觀測 actor 重播與 restart 時序核對。維持原 run 停止，不改 reward、終止門檻或 guard，不自動回滾。

離線衍生資料位於忽略的 diagnostic_packages/regression_20261016/；initial_divergence.png 比較前12秒的 guidance d、roll 與 action。

## 第二包與相同觀測重播（2026-10-16）

收到 regression_models_20261016_161913.zip，ZIP CRC 通過，共1807個檔案。Agent18400／18500／18600逐檔SHA256與先前evaluation.json一致。檢查attempt197–204的啟動預檢紀錄，環境及引擎SHA均相同；這是預檢證據，不等於完整歷史執行封存。

- 18101起已有較多短回合，不能說所有退步只發生在18401後。
- attempt201涵蓋18401–18500，全段6 workers。每20回合的平均reward/steps依序1592.9/1838.2、2211.2/2565.2、1705.7/1985.7、951.3/1113.2、179.7/236.0。
- attempt202在18501前建池失敗；attempt203才降成4 workers。因此這次降級發生於崩落之後，不能解釋attempt201內的崩落。也不能據此排除所有先前重啟影響。
- training_options／initial snapshot：本包含TrainingOptions，沒有Agent_Initial；未做重啟前後初始權重一致性認證。

對每個checkpoint載入CPU actor，將LSTM狀態歸零，依序evaluate各自已記錄的觀測（最多150步）。三者對自己的trace都與記錄action完全一致，最大誤差0；evaluate前後actor可學參數完全相同，沒有模擬或訓練。

再把18400的同一串150步觀測分別送入三個actor；相對18400，18500動作平均絕對差0.183126、最大0.504293；18600平均絕對差0.553144、最大1.084608。各自LSTM狀態由同一觀測序列演化，並非強迫其隱狀態相同。這證明不同checkpoint對同一輸入歷史的策略輸出不同，不能只歸因於抽到不同路徑；但離線重播不證明換上另一actor的閉迴路結果，也不識別學習率／optimizer／PPO更新的因果。

工作檔：diagnostic_packages/replay_regression_actors.m、regression_20261016/actor_replay.json。沒有修改正式runtime、checkpoint、課程或啟動正式訓練。後續應採保留父run的受限恢復試驗與獨立評估，不應直接續訓18600或放寬reward門檻。18000在先前小樣本評估通過，可列為候選；18400訓練已不穩定且直線初始擺動較大，不稱最佳恢復點。

## 實驗室減半LR分支：18300暫停後評估

使用者提供分支20261016_162607_recovery_tpf699ae87的四次直線seed501 CPU評估輸出，evaluation_20261016_192536_tpcebd1553。18000/18100/18200均3000步，reward3017.65066/2981.10267/3014.16667；18300僅79步、49.33425，末端guidance d約50.036m，獨立原路線距離最大50.036m在7.9秒，after10無樣本。

分支18000的直線結果與原父run先前同情境結果一致，支持準備分支沒有破壞這項凍結策略表現；不能據此宣稱每次attempt的Agent_Initial、optimizer或worker初始化皆正確。需要實際初始快照核對。

18100/18200雖跑滿，10秒後獨立距離RMS為4.910/4.001m（18000為2.707m），最大40.532/39.169m（18000為29.339m）。reward近似不代表暫態偏離同樣小。直線能力崩落可定位於已保存18200至18300之間；不是證明整段退步從18201才開始。這是Stage1的固定診斷，不是訓練Stage4或所有任務的評估。

本次actor LR減半沒有避免這個分支的崩落；不以不同隨機訓練分支比較推論減半有害或學習率完全無關。保留暫停、不自動從18200再續訓。下一步收集此分支18000–18300 checkpoint、三段Agent_Initial與TrainingOptions、日誌及這次詳細traces；不再要求重跑相同評估。資料尚未傳入本機，不能把前一個run相同episode檔案混用。

## 第三包：初始快照核對與恢復分支重播

收到 recovery_review_20261016_192959.zip，50個檔案，ZIP CRC通過。四個checkpoint SHA256皆符合本包evaluation.json。三個attempt環境／引擎預檢SHA一致，皆6 workers；seed依序10001–10006、20001–20006、30001–30006。

離線讀取r000001/r000002/r000003的Agent_Initial與對應18000/18100/18200，三者Actor及Critic可學權重逐值完全相同；Actor保存State和公開AgentOptions亦isequaln相同。後兩段resume路徑為Agent_Final，但已用實際快照權重對照同回合checkpoint，未用檔名推論一致性。沒有檢查optimizer私有狀態或worker執行時隱狀態，故不能宣稱所有resume問題都排除。

第三段18201–18220平均1698.65步、11/20跑滿；18221–18240平均1112.5步、7/20跑滿；18241–18260平均88.65步，18261–18280平均83.65步，18281–18300平均83步，後60回合皆未跑滿。嚴重崩落發生在第三段內，且第一段後半已出現較多短回合。

四個actor對各自既有觀測做CPU離線重播，前最多150個action最大誤差皆0，可學參數前後不變。使用18200同一串150步觀測及零初始LSTM狀態，18300相對18200動作平均絕對差0.407212、最大0.731470。此為輸出變化，不稱KL或單次PPO更新幅度，不能由此判定clip失效。

結論：沒有載錯／重設可學權重的證據；低LR仍發生段內策略退步。應調查更新前後行為變化、訓練探索與固定評估的差異，而非直接第三次減半或改reward。這批資料已足夠接續離線分析，無需再次要求使用者重跑同一組評估。工作檔為diagnostic_packages/inspect_recovery_resume.m、replay_recovery_actors.m及recovery_review_20261016/offline_resume.json、actor_replay.json。本次無模擬、訓練或正式runtime修改。

## Stage4新路徑配對評估：2026-10-16 19:41

使用者貼回evaluation_20261016_194120_tpd47c04a4完整終端summary：恢復分支18000／18100／18200在random_calm、seed601:606，各6/6跑滿3000，平均reward2895.31095／2867.34043／2900.91153，mean_observation7_rms分別0.187201／0.241393／0.221085。這是凍結策略、關閉探索的6條路徑診斷，不是泛化成功率或課程合格。

修正先前待驗證假說：18100與18200不只是保有直線能力，也保有本次六條隨機路徑的確定性執行能力。18200reward略高於18000，但guidance距離RMS較大，不能單憑reward稱更好。未收到route_metrics完整內容，不把observation7_rms冒稱獨立原路線誤差。

訓練中大量短回合與凍結評估全跑滿之間仍有差異：探索、訓練中變動權重、路徑抽樣、並行執行等因素尚未分離；不宣稱探索已證實為根因。下一個有辨識力的對照是同一checkpoint／環境／路徑、凍結權重下的探索開關比較；現有compare_training_checkpoints固定UseExplorationPolicy=false，尚不支援選項，不給不存在的參數、不建議直接關閉訓練探索。保持暫停，18300已確認策略能力崩落，不因18200測試良好而自動續訓。

## 探索開關實驗室對照：2026-10-16 19:58

使用者貼回evaluation_20261016_195803_tpcc57bafc，CPU固定模型、Stage4 seeds601:606、useExploration=true。18000為6/6跑滿，mean reward2628.94638；18100及18200皆5/6，mean reward2155.28250／2174.77856。兩者皆seed601於101／99步提前終止，terminal observation7約1.6708／1.6707，對應guidance d約50.12m；只是終端門檻證據，未收到詳細trace做物理分支確認。

相同六個seed關閉探索時三者均6/6。這支持18100／18200對此次動作抽樣的容忍度較18000差，確定性跑滿掩蓋了脆弱性；不是探索過大已證實，更不是獨立樣本失敗率16.7%的可靠估計（共用seed、少量配對、同起始區段）。18000探索六例皆跑滿，不應全面關閉探索。不能以此獨自解釋18300確定性能力崩落或所有並行訓練失敗。

下一步不再要求新模擬：取得上述探索組及evaluation_20261016_194120_tpd47c04a4確定性組的既有trace與scenarios，配對seed601檢查初始觀測、動作抽樣／均值、位置與距離。已持有三個checkpoint，不再要求重傳。routeMetrics=true僅位置，不能冒稱有完整guidance／姿態診斷；experience內可讀觀測與動作。保持暫停，不回滾或盲目再降LR。

## 配對trace離線分析（2026-10-17）

exploration_pair_20261016_200348.zip共40檔，CRC通過；兩份報告環境SHA相同，checkpoint SHA與本機恢復包一致，scenarios.mat的scenarios逐值相同。六份seed601 trace重播確認關閉探索action與actor均值一致、actor權重不變。

seed601前15秒 guidance d峰值：18000關閉探索30.968m、開啟37.153m；18100關閉40.883m、開啟50.125m（10.1秒結束）；18200關閉40.533m、開啟50.121m（9.9秒結束）。可見平均策略起始暫態本已更接近50m門檻。開啟探索前5秒沿各自trace的actor std均值18000=0.41670、18100=0.42323、18200=0.43342；不是標準差突然數倍爆炸。

在三者共同前99個動作的未超過名義範圍樣本，(action-mu)/sigma相對18000最大差約1.75e-7／2.44e-7，支持此次配對使用相同標準化隨機抽樣，而不是18100／18200碰巧抽到完全不同的噪音序列。此比較僅限該seed與樣本，不能推廣到所有訓練隨機性。

部分experience原始action超出[-1,1]，例如t=6s三者-1.182/-1.255/-1.245。這不能單獨當成bug或實際舵面超限：靜態SLX檢查RL輸出進inner loop及延遲／記錄分支；模型包含其他不同物理量的限幅，不能看到Saturation就宣稱action被clamp。現有action_saturation_fraction只是abs(action)>=0.99比例，不是已驗證的物理飽和比例。

較精確結論：此次失敗與原有起始暫態裕度變小、探索擾動共同出現；沒有證實只縮小std即可恢復可訓練性，更沒有識別均值策略為何被更新至脆弱區域。不能取消探索或放寬50m來假裝修復。本輪未訓練、未模擬、未更改正式環境。
