# Stage 6 歷史路徑有效範圍調查

## 範圍

本次使用者授權繼續隔離評估。正式 runtime/FAFA_Simulation.slx 與原 checkpoint 不修改；所有模擬使用診斷包解出的副本、CPU、關閉探索，不 train、不啟動 pool。工作區既有程式註解與文件重組未覆寫，也未將它們納入提交。

兩包來源及完整性：

- 主包 `diagnostics_20261012_080431_recovery_tpfaf0be04_ee09c9b1.zip`，SHA256 `cbed0437d94e4c295cf829bd29a08cb57a32310eb5f18d81ded2759663d84e83`，380個manifest項目全部驗證。
- 補充包 `stage6_extra_579587cc961c4f62978679a58f403a7e.zip`，SHA256 `878dbc48ebdb6d5caceee3e6efda4976cf44562688b0ff354e0d79c672231025` 與使用者提供的一致，ZIP CRC通過。
- 評估來源SLX與本機相同，SHA256 `b28c5a5c967347c498cb23f032b483841ca63b98ab4da137ca902e193225714c`。程式註解可能不同，不能因此宣稱所有runtime歷史指紋相同。

## 已證實的問題

guidance 的 `global_path` 預配置500000列，`path_length`代表已填入列數。原 `path_CTE=global_path` 包含尾端零值。outside分支找到最後有效點時，`current_index+1`仍在配置大小內，因此把它連到未使用的 `(0,0)`，不是有效路段。

用記錄的planned_path串接，重算全部12個失敗trace。202/204/205跨三個checkpoint的9次終端誤差與末點接零座標的假線段計算值吻合至小數6位；207則選到已填入的內部路段，不能全部歸為相同原因。

31600的202/204/205終端logged d為50.424913/50.895169/50.180986m，而末段延長線側偏7.017/1.549/2.891m。延長線不等於有限路徑或未來期望路徑，不能據此宣稱飛機已完成真正循跡。207有真實約50m偏離與更新後轉向問題。

## 最小候選

`compare_training_checkpoints(...,guidanceVariant="valid_history")` 只把暫存guidance改成 `path_CTE=global_path(1:path_length,:)`。有效末點會走原有末段分支，不再連到零值。不更動lookahead、reward公式、終止門檻、planner、更新頻率或模型參數。

因距離也是observation/reward/termination的輸入，改正距離會改變閉迴路動作及分數。即使回合延長，也不代表agent重新學習或真實循跡已合格。此候選仍使用原無限直線橫向距離，而非將所有距離改成有限折線最近距離。

輸入MAT未包含在診斷包；只在本機解壓副本，從已提供的前三階段evaluation/scenarios.mat還原相同waypoints/velocity，未生成不同路徑、未改課程JSON。診斷副本只是評估材料，不可用它直接續訓。

## 驗證

`tests/test_history_candidate.m` 已通過：非原點直線末端越過時排除假線段、5m側偏保留、inside目標及距離不變、重複轉換拒絕。

本機 baseline 31600 / Stage6 / seeds202,204,205,207 重現實驗室2596/998/695/730步及對應reward。初始權重稽核原報告initial_snapshot_count=0，不能聲稱已核對全部接續時刻的initial/resume一致性。

本輪共27次CPU純sim完成（4 baseline +20 candidate +3 retention）。候選小風10/10、完整風6/10，前三階段3/3。正式SLX雜湊與所有被評估checkpoint雜湊保持不變，sim前後權重檢查通過。

| Stage6 seed | 原版步數 | 有效歷史候選步數 |
|---|---:|---:|
|202|2596|2715|
|204|998|1111|
|205|695|1417|
|207|730|730|

完整風平均reward從2262.88到2359.97，平均steps2301.9到2397.3，完成數未增加。小風平均reward3036.81；前三階段reward及RMS與原版相同。不能把修正後reward提高當成學習改善。

候選終端已不是同一零值誤索引：202/204/205/207的logged d為50.18/50.93/50.82/50.53m，對當前有限planned_path獨立計算的最近距離吻合約0.01m內。更新前可見沿舊末段延伸已越過路徑末點約74~109m；269.9/109.9/139.9/69.9s新path更新後，目標/轉向需求大變，終端目標在機頭後方。WindowManager仍每步前移一個waypoint且每100步valid，而飛機地速隨風變化；目前只定位了時間推進與實際進度不一致的症狀，尚未驗證新的planner策略。

評估資料（均在忽略的diagnostic_packages/stage6_review/main/reports）：baseline evaluation_20261013_191041_tpf4c1cd04；candidate evaluation_20261013_191142_tp9695204b；retention evaluation_20261013_191447_tpadf7f19a。下一步需隔離驗證前方路徑不足／更新跳變的處理，並明確保留任務的空間或時間跟隨語義；本輪不部署正式環境、不重啟訓練、不放寬終止門檻。
