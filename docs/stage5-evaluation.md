# Stage 5 暫停後診斷（2026-10-11）

實驗室在 21600 因 recovery_budget 正常暫停。11600/21600 的前三項無風評估顯示能力保留，但不回答 Stage 5 低分原因。先保持暫停，做隨機路徑的配對無風／小風擾診斷，不調 LR 或過關門檻。

取得本次更新後，在 MATLAB 專案路徑可見、FAFA_Simulation 未開啟時執行：

```matlab
clear compare_training_checkpoints
rehash
root = fileparts(which("compare_training_checkpoints"));
session = fullfile(root,"experiments","progressive_v1","runs", ...
    "20261010_224522_recovery_tpc1c4f06e");
evaluation = compare_training_checkpoints(session, ...
    episodes=21600,includeLatest=false,stages=[4 5],seeds=201:210);
disp(jsonencode(evaluation.summary,PrettyPrint=true))
disp(jsonencode(evaluation.results,PrettyPrint=true))
```

共 20 次 CPU 串行 sim、每次最多 3000 步，沒有訓練、pool 或自動續訓；可能耗時，逐次寫報告。對每個 seed，Stage 4/5 使用完全相同的隨機路徑；每組 checkpoint 都重用保存的 scenario。風場依課程整數範圍抽樣，某些小風擾樣本可能抽到全零，逐列記錄實際值，不將其偽稱有風。

路徑產生器複製自訓練引擎，執行前檢查函式一致性，未修改 runtime。評估每個 seed 生成一條路徑；不重現訓練 worker 每十回合刷新與探索的歷史序列。探索關閉，不能直接把評估 reward 當訓練曲線的同分布樣本。

`evaluation.summary` 每個 checkpoint/stage 提供樣本數、跑滿比例（排除同時 IsDone）、平均 reward/steps、每回合 observation7 RMS 的平均、最低 reward 的 seed/trace。只有 10 個診斷情境，不是正式可靠度或泛化合格證明。若小風擾較差，需依實際風參數與最差 traces 檢查；若兩者皆好，也不能單憑此斷言所有訓練失敗都是探索造成。

`evaluation.results` 有實際 east/north/turbulence、終端原始 obs3/obs7、obs7 最大絕對值與 `termination_evidence`。此欄只是已審視觀測正規化下的終端門檻證據；unknown 保持未知，不猜測物理原因。完整軌跡和風存於 `scenarios.mat`，experience 存於各 trace，並保存 SLX/engine/產生器/課程/checkpoint SHA256。

Simulink 內部亂數 seed 沿用模型保存值，MATLAB seed 並不獨立重設所有噪音來源。因此跨 seed 主要變化為路徑與抽樣風參數，不宣稱每次都有獨立 turbulence 時序。輸出報告明確保留這項限制。

結果仍位於 run/reports/evaluation_*，受 Git 忽略。貼 summary 與 results 即可，先不傳完整 MAT。純評估不解除 training guard 的暫停。

## 本機驗證

`tests/test_wind_evaluation.m` 通過配對路徑一致性、不同 seed 路徑差異、RNG 還原與合成終端門檻案例；使用既有短測 agent 完成四次各五步的真實 CPU 模擬（含強制非零風及 turbulence）。`tests/test_checkpoint_comparison.m` 另通過六次各五步固定路徑/MAT 模擬。source SHA、agent 權重與 caller RNG 檢查通過。這是工具整合短測，未執行訓練，未測試實驗室 21600 的表現或完整 3000 步隨機風擾可靠度。

## 規劃與導引訊號重播

初次 20 次評估發現205/207有風失敗、210同風況成功，離線發現見 [trace 調查](stage5-trace-findings-2026-10-11.md)。需要更多訊號時：

```matlab
clear compare_training_checkpoints
rehash
root=fileparts(which("compare_training_checkpoints"));
session=fullfile(root,"experiments","progressive_v1","runs", ...
    "20261010_224522_recovery_tpc1c4f06e");
detail=compare_training_checkpoints(session,episodes=21600,includeLatest=false, ...
    stages=[4 5],seeds=[205 207 210],diagnostics=true);
disp(detail.outputDir)
disp(jsonencode(detail.results,PrettyPrint=true))
```

共6次完整CPU純模擬。`diagnostics=true` 在系統暫存資料夾建立同名 SLX 副本，只在記憶體中啟用14路 signal logging，不改 chart 或控制演算法、不存回原模型。每個 trace 新增 `diagnostics` Dataset，記錄 E/N位置、psi/phi、完整 planner path、window path/valid/loiter/target distance、guidance target E/N、d、delta_psi、heta。完整可變長度路徑可能增加檔案大小；僅對指定少數情境使用。

以 [MathWorks sim 文件](https://www.mathworks.com/help/reinforcement-learning/ref/rl.env.rlfunctionenv.sim.html) 的 `experience.SimulationInfo(1)` 取得 SimulationOutput 內的訊號資料。報告保留訊號來源 block/port；缺少必要訊號直接失敗，不以空紀錄冒充完成。這仍未直接記錄 guidance 內部 current_index/is_inside；可用實際位置及輸出路徑離線核對幾何，但有歧義時不能自行假定內部分支。

請先將這次6個 reward/steps與原始205/207/210的結果比較；若不一致，須調查重播差異再推論失敗原因。最後將新的 evaluation 資料夾壓縮分享，包含新增 diagnostics 的 traces，無需 checkpoint。本機没有21600 agent，因此完整實驗室重播仍需在實驗室執行。

2026-10-11 本機 `tests/test_evaluation_diagnostics.m` 通過：同 checkpoint、seed、random 路徑分別做一般與 diagnostics 模式各110步 CPU純模擬，reward、observation、action逐值完全一致；取得14路訊號並跨過約9.9秒的週期更新，原SLX SHA256不變。這不是21600實驗室模型的完整重播驗證。
