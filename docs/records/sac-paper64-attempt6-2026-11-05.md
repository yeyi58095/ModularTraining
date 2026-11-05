# SAC 隨機路線第六段歸檔

遠端原件為 `D:\daniel\ModularTraining\artifacts\packages\sac-paper64-attempt6-20261105-181421.zip`。本機從專案根目錄的同名檔移至 `artifacts/incoming/sac-paper64-attempt6-20261105/`。大小 128937783 bytes，搬移前後與遠端提供的 SHA256 均為 `08BF78870B7A48C951846DEF933FF43064734B3502C74BD660804A1492E69E35`。

包內 run 為 `20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580`。11 月 5 日 18:04（臺灣）控制器因達設定的 attempt 上限轉為 paused。stdout 顯示正常保存，包內有 Agent500.mat 及 Agent1600.mat。curriculum_outcome.json 記載第 1600 回合仍為 Stage 1 random_calm，決策 continue / conditions_not_met。

下列統計直接取 attempt_00006/stdout.log 每回合 reward 與步數，每列 100 筆，從 1101 起只採用本次續訓資料。

| 回合 | 平均 reward | 平均步數 | 跑滿 3000 步 |
|---|---:|---:|---:|
| 1101–1200 | 1903.92 | 2398.39 | 62% |
| 1201–1300 | 2045.48 | 2548.24 | 63% |
| 1301–1400 | 1901.17 | 2375.79 | 62% |
| 1401–1500 | 1956.65 | 2472.24 | 60% |
| 1501–1600 | 1902.81 | 2398.24 | 57% |

正式 outcome 另記 averageReward 1936.2455；上表採用 stdout 的一致窗口口徑，兩值差異原因待核。與[第 401–500 回合](sac-paper64-first500-analysis-2026-10-30.md)的 1974.51、2526.22 步及 66% 相比，後段沒有顯示持續提升。訓練路線與探索不同，不能單據此判定兩份模型孰優。下一步可凍結 Agent500、Agent1600，在相同路線與風況配對比較，再決定是否另設提早引入弱風的課程。本次僅查閱封存，未載入模型或執行評估。
## 遠端下一步：比較 500 與 1600

在遠端新開 MATLAB R2024b，讓已暫停的 run 保持暫停。以下使用既有 CPU 評估入口，讀取 run 的環境與課程快照。選五個預先指定的 seed，讓兩個 checkpoint 在相同路線分別測無風與弱風。每個 stage 的實際風分量以 evaluation.json 為準。

```matlab
cd('D:\daniel\ModularTraining');
addpath(pwd);
sacDir = string(strtrim(fileread(fullfile(pwd,'artifacts','sac-random-route-v1-run.txt'))));
[~,runId] = fileparts(sacDir);
assert(runId == "20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580");
model = jsondecode(fileread(fullfile(sacDir,'model.json')));
env = jsondecode(fileread(fullfile(sacDir,'environment.json')));
state = jsondecode(fileread(fullfile(sacDir,'status.json')));
assert(strcmp(model.name,'sac_paper64') && strcmp(env.id,'spatial_v2'));
assert(strcmp(state.state,'paused') && state.attempt == 6);
report = compare_training_checkpoints(sacDir,episodes=[500 1600], ...
    includeLatest=false,stages=[1 2],seeds=501:505,maxSteps=3000, ...
    useExploration=false,routeMetrics=true);
assert(strcmp(report.status,'complete') && numel(report.results)==20);
disp(fullfile(report.outputDir,'evaluation.json'));
```

先回傳最後印出的 evaluation.json 即可。按 stage 與 seed 配對比較跑滿率、步數及後段路線偏差；同時檢查提早結束的回合，避免短軌跡的小偏差被當成改善。五條路線可用來篩選下一輪實驗，接近或結果分歧時應增加新路線再判斷。若 500 在無風及弱風都相近，可另開提早加風分支並保持 SAC 配方一致；若 500 在弱風明顯較差，優先保留較長無風階段。此次比較獨立於正式課程升階判定。
