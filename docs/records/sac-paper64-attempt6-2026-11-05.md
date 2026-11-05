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
### 五條配對路線的實測結果

遠端報告 `reports/evaluation_20261105_182328_tpf9b87cd5/evaluation.json` 由本機專案根目錄移至 `artifacts/incoming/sac-paper64-paired-20261105/evaluation.json`，搬移前後 SHA256 均為 `1FBA21F8E59BED69625251EF422A9B7D2CAEAC99B7E5A051357946050B562E0D`。run ID 符合，spatial_v2，CPU 關閉探索，20 筆完成，報告記載權重核對通過。

| 階段 | checkpoint | 跑滿 3000 步 | 平均步數 | 平均 reward |
|---|---:|---:|---:|---:|
| 無風 | 500 | 2/5 | 2082.4 | 1531.51 |
| 無風 | 1600 | 4/5 | 2582.0 | 2112.89 |
| 弱風 | 500 | 2/5 | 2098.2 | 1565.77 |
| 弱風 | 1600 | 4/5 | 2582.0 | 2110.82 |

501、505 在弱風階段抽到零風，與各自無風結果相同。其餘三條有風路線上，500 跑滿 2/3，1600 跑滿 3/3。502 在東、北風分量皆為 −1 m/s 時，500 於 608 步結束，1600 跑滿；10 秒後原路線水平偏差 RMS 從 20.80 m 降到 5.93 m，兩條軌跡時長不同。503 兩者都跑滿但弱風 RMS 從 7.16 m 升至 11.12 m；504 都跑滿且從 12.75 m 降至 10.37 m。505 兩模型皆提早停止，1600 只飛 910 步，500 飛了 2753 步。報告無終止點座標或逐步控制軌跡。

這批配對支持額外無風訓練對部分路線有幫助。暫保留原課程與 SAC 配方。若要找介於 500 和 1600 的引風時機，下一次可加入 1000 checkpoint，與兩端在新路線 506–515 配對；分開統計實際有風、零風與各路線退步案例。此為候選課程設計依據，正式升階另依原 run 的條件決定。
