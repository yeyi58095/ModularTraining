# 實驗室 recovery 原始資料分析

來源 ZIP：diagnostics_20261010_155437_recovery_tpebed29a8_e44b46f8.zip。
SHA256：EF62BE13F96E990C24992ABED900ADA3FFA4D2D775D27C4C700CE07E48A37C84。
整包及 manifest 38 個檔案均驗證通過。MAT traces 僅載入與匯出數值，沒有 sim 或 train。來源 ZIP、解壓內容與分析圖保留在被 Git 忽略的 diagnostic_packages/。

## 可確認的提前終止機制

evaluation.json 記錄的 FAFA_Simulation.slx SHA256 與本機 runtime 模型一致。OBSERVATION 的 Mux (SID1628) 第7路來自 Normalization (SID1643/chart86)，輸入為 guidance_law 的 d、finite=30 (SID1642)，因此 observation7=d/30；第3路 phi 以40度正規化。d 同時由 OBSERVATION 第3輸出直送 isdone。

isdone/system_362 的有效路徑是 abs(d)>=50 (SID1991) 以及 phi>=40度、phi<=-40度，經 OR 接到 RL Agent。其他同名舊比較器有 Commented=on，不應誤當有效條件。

|Checkpoint/任務|步數|最後 d（模型計算，m）|全程最大絕對滾轉角（度）|
|---|---:|---:|---:|
|10600 直線|3000|2.455|9.528|
|10600 S彎|3000|0.876|9.528|
|10600 固定轉彎|1578|50.081|14.438|
|10700 直線|133|50.247|15.579|
|10700 S彎|134|50.395|15.579|
|10700 固定轉彎|133|50.276|15.579|
|11000 直線|144|50.197|20.683|
|11000 S彎|144|50.352|20.683|
|11000 固定轉彎|144|50.116|20.683|

所有提前結束的 trace 都是最後 observation 首次跨過 d=50，前一點仍低於門檻，且全程未達 roll ±40度。因此資料支持此次 IsDone 由模型的路徑誤差門檻觸發；不支持「滾轉超限」或「動作飽和」的解釋（既有評估 action_saturation_fraction=0）。這是模型計算的 d，不代表已獨立驗證其幾何計算完全正確。

## 變化時間

直線任務初始 observation 都為零，但第一個 action 已不同：10600=-0.0529635，10700=-0.0342917。約3秒時 action 分別為-0.0233／0.3479；13秒時 d 為9.216／45.751m。10700 並不是到轉彎才失效。

前約10秒 d 都回報0；guidance_law 在 numWps<2 時會直接回傳預設 d=0，WindowManager 亦定期才提供 valid_flag。不能把這段零值當作已證明完美循跡。後續應優先核實路徑就緒前的觀測與控制過渡，但這尚不是已證實的訓練退步根因。

首次 attempt 每10回合平均步數：1041.2、950.7、1052.3、753.1、984.1、622.8、384.3、343.0、137.4、137.0（10601起）。所以訓練表現是在同一 attempt 內逐步變差，不能只歸因於每100回合重啟或切換stage。r000001 訓練腳本與本機引擎正規化換行後文字一致；原始位元組雜湊不同，不宣稱二者原始檔完全相同。

## 限制與下一步

此前 audit 已證實 train 前初始快照與10600可學習權重一致。現有證據把問題縮至訓練更新後的閉迴路行為差異，但尚未檢查 optimizer 內部狀態、每次 PPO 更新的 KL／entropy 或 recurrent state。固定條件單 seed 不是泛化測試。

保留10600，保持現有分支暫停。下一步優先檢查路徑初始有效訊號與前10秒控制，並在相同觀測序列下比較 actor 分布／recurrent state，避免把不同閉迴路 observation 的 action 差異全歸於單一步輸出映射。沒有根據將 learning rate 再減半、放寬50m門檻或啟動新長訓練。

## 同觀測序列重播與初始化驗證

離線載入10600／10700 actor，在CPU逐點evaluate，初始LSTM state設零，每步接續evaluate回傳的state。各自重播自己的直線trace時，前150／133個action與保存結果最大差異均為0，確認時序及狀態更新相符；可學習權重前後不變。未呼叫train或sim。

兩個actor都讀取10600直線trace的前150步：平均絕對action mean差異0.36509，最大0.56311；高斯標準差平均由0.52111變為0.42137。第30步均值-0.02331對0.42045，第50步-0.17990對0.37936。均值在相同觀測歷史下已有明顯偏移，並非僅由兩次飛行軌跡不同造成。讀取10700前133步時，平均絕對均值差異0.26944、最大0.49837。這不等於已證明LSTM損壞，也不等於所有狀態都退步。

原始未截斷高斯分布的離線 KL(10600||10700) 在10600 trace平均0.55715；此非訓練rollout上的逐次更新KL，也不是PPO clip_factor=0.2的直接比較對象，不以此宣稱PPO clipping故障。

### 路徑啟動空窗已確認

模型OBSERVATION/Constant4(SID1963)=100，接入WindowManager(SID1902/chart60)的window_length。該block取樣0.1秒，buffer_counter由1開始，只在mod(counter,100)==0時valid。planner(SID1891/chart118)初始stored_path_length=1，valid以前只回傳一點路徑；guidance_law(chart167)對少於2點路徑回傳d=0、heta=0等預設值。

直接從同SHA256的SLX抽出純函式測試：101次呼叫中原WindowManager只在第100次valid；單點路徑即使給定位置偏移80，guidance_law仍回傳d=0。這證實起始約10秒的零誤差是路徑未就緒時的預設輸出，不能當作有效循跡資訊。其他觀測仍有姿態、位置等，不是全部輸入都為零。

在診斷目錄的獨立副本中，將valid條件改為counter==1或原週期條件，純函式測試valid呼叫變成[1,100]，保留後续週期。尚未改runtime/SLX，也未跑該候選的閉迴路評估。此初始化缺陷可能使策略對啟動行為更敏感，但尚未證明它是10600→10700更新退步的唯一原因。

下一個有辨識力的比較：用獨立模型副本、相同checkpoint與seed、零訓練，對照原版與首次就緒候選的前段行為及完成步數。不能直接覆寫既有實驗的環境來續訓；修正初始化會改變任務分布，需要另留環境版本。

API依據：[MathWorks evaluate](https://www.mathworks.com/help/reinforcement-learning/ref/rl.function.rlcontinuousdeterministicactor.evaluate.html)（高斯均值／標準差及nextState）。
