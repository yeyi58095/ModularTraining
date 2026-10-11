# Stage 5 失敗 traces 離線檢查

來源：使用者提供 stage5_evaluation_20261011_205243.zip，ZIP CRC 通過，包含 20 個 trace、evaluation.json、scenarios.mat。評估 SLX SHA256 與目前本機模型一致。純 MAT 讀取與數值分析，沒有 sim/train 或模型修改。

21600 在十條 random 無風路徑全部跑滿，小風擾為 8/10。由 scenarios.mat 直接核對 seed 205、207、210 在 stage4/5 的 waypoints 完全相同；這不代表有風閉迴路中規劃器產生的路徑也相同。

| Seed | 有風結束時間 | 終端模型 d | 全程最大 abs roll | 同路徑無風最大 d |
|---|---:|---:|---:|---:|
|205|104.2 s|50.094 m|19.54 deg|15.804 m|
|207|74.3 s|50.146 m|19.83 deg|12.443 m|

d=obs7*30、roll=obs3*40，依相同 SHA 的模型正規化。兩次皆首次跨過 d=50，roll 未達 ±40，action 未達 ±0.99；不能解讀為 roll 超限或 actuator 飽和。這是模型計算的 d，不是獨立幾何真值。

兩次最後失敗段皆連續增長，不是單次數值跳過門檻：205 的最大正 d 增量 1.535 m/0.1 s（102.9 s），207 為 1.509（73.1 s）。205 在 99.8 s d=2.63、100.8 s d=4.12、102.8 s d=29.93、104.2 s 超過50；207 在69.9 s d=3.34、70.9 s d=3.24、72.9 s d=29.93、74.3 s 超過50。之前也有明顯誤差峰值並回落。

動作反向：205 從99.8 s +0.660到100.3 s -0.486；207 從69.8 s +0.683到70.3 s -0.516。roll 隨後由正轉負。兩次時點接近 WindowManager 的每100次更新（0.1 s取樣，約99.9/69.9 s）；只有時間上的關聯，不能斷言重規劃造成失敗或動作方向錯誤。

205 風為 east=1,north=1,turbulence=0；207為1,-1,0。相同205風況的210能完成3000步，最大 d=22.224m；因此不是這個風設定必然失敗，也不能將原因單獨歸給 turbulence。

現有 experience 沒有實際 E/N 位置、每次 planner path、選中路段與 guidance 內部分支。scenarios.mat 是輸入軌跡，不能當作實際規劃器輸出。尚不能區分策略追蹤不足、規劃路徑突變、目標選擇／距離計算問題。下一步宜在評估副本增加上述訊號記錄並只重播205/207及成功210，保持原 runtime、checkpoint、課程和 guard 不變；不要據此直接改 LR 或放寬終止門檻。

本機忽略資料：diagnostic_packages/stage5_arrays.json、inspect_stage5.m、stage5_failure_analysis.png；原ZIP與解壓資料保留。沒有執行新的模擬，亦未提交／上傳原始資料。
