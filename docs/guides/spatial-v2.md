# spatial_v2：獨立的新版 reward 環境

2026-10-15，使用者授權建立 `environments/spatial_v2`，主要改 reward，並要求將進度記入 AGENTS／README 供其他聊天室接續。

## 版本與修改位置

- 環境 id：`spatial_v2`；reward id：`spatial_reward_v2`。
- 模型：`environments/spatial_v2/FAFA_Simulation.slx`。
- 新模型 SHA256：`997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557`。
- 父版本：`spatial_v1`；父模型 SHA256：`495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be`。
- manifest：同目錄 `environment.json`；新建 run 時由現有環境快照機制驗證並複製。

正式計分已寫入這份獨立 SLX，並非只有離線候選函式。原 `runtime/FAFA_Simulation.slx`、spatial_v1 及所有既有 run 快照均未更動。

只有 `OBSERVATION/MATLAB Function13` 與 `OBSERVATION/MATLAB Function22` 的程式改變。SLX 存檔另外更新模型 UUID、版本號和視窗／metadata，沒有更動模型接線、guidance、WindowManager、observation、IsDone、PPO 或其他 reward 支路。

## 新公式

使用先前離線校準的最小修改候選，距離懲罰強度固定 w=0.2。以下 d 單位為公尺，是 guidance 的局部橫向距離，不是原始有限折線的獨立最近距離：

```text
cross_track = 0.2 - 0.2 * d / 30
distance_bonus = 0.1 + 0.05 * max(0, 1 - d / 10)
```

Function13 保留原輸入介面，直接傳遞正規化 d，取消依曲率將直接距離懲罰減半；既有下游 Gain／Abs 完成第一條公式。Function22 將輸入 d/30 還原成公尺後，計算 10m 內的連續加分，取消舊局部 waypoint 距離30～150m加分。

原有0.1基底仍保留；獨立 curvature_distance、朝向、角速度、轉向追蹤、距離變化及動作扣分均保留。沒有宣稱已解決所有 reward 投機行為，也沒有提高懲罰強度到0.4或0.6。

## 評估與重現

`instrument_reward` 會辨識兩個 chart 的新版標記並寫出 reward_version。`trainingtools.audit_training_rewards` 依記錄版本核對逐步得分，舊報告沒有版本欄位時仍依舊公式處理。混合標記或不相符的數值會拒絕；不把新版 traces 當舊公式分析。

```matlab
addpath('tests');
test_reward_breakdown();          % 原公式相容性
test_spatial_reward_candidate();  % 候選單位與單調性
test_spatial_v2();                % 直接讀實際 SLX 的兩個 chart 驗證
% 需要本機既有診斷 checkpoint/traces，會純 sim，但不 train：
% report = test_spatial_v2_simulation();
```

建置工具為 `environments/build_spatial_v2.m`，只用於作者從固定的 v1 產生新 bundle；若 spatial_v2 目錄已存在就拒絕覆寫。一般使用者同步完整 bundle 即可，無需重新建置。後續修改已使用的版本應另建版本，不直接改既有 run 快照。

### 本次驗證結果

- 直接讀取 v1/v2 全部 Stateflow MATLAB Function 程式，比對確認只有上述兩個 chart 不同；128組距離／曲率／目標距離組合與候選公式相符，版本錯配會拒絕。
- 在獨立診斷測試副本，以 Agent31600、Stage6 seed205 做 CPU、關閉探索的3000步純 sim；實際抽樣風 east=2、north=3m/s、turbulence=0。這一例不代表所有風場或 turbulence 等級。
- 原分數2823.4247706269057，新分數2666.4952715484128；實際 SLX 與離線重計分逐步最大差 `4.4408920985006262e-16`。
- 比對位置、姿態、guidance d 與動作變化扣分，最大差均小於1e-8；evaluator 核對模擬前後權重一致，來源 checkpoint SHA 未變。來源 checkpoint SHA 為 `75bc17b133c86c974b11ebfbb23be385e9965605323486b2ff36891626c8e823`。
- 精簡收據：`tests/output/spatial_v2_validation.json`；評估資料夾：`tests/output/tp2eb7dbee_c5ab_4a8f_8985_05e265193c95/reports/evaluation_20261015_135821_tp58ac2704`。兩者為本機忽略資料，完整 traces 不納入 Git。
- 舊 reward 合成測試、候選單位／單調性測試、新版診斷與新 run 快照預檢通過。沒有 train、GPU／多 worker 驗證或長期收斂結論。

## 與 progressive_v2 的關係

**後續使用者明確要求 progressive_v2 使用 spatial_v2，已更新共享課程及遠端設定。** 原有 reward 門檻維持起始方案，尚未針對新公式長訓練校準，不宣稱能保證收斂。

使用者已在遠端準備的 `20261015_134932_tpfcac90bf_7392_48ff_b6d6_e7b07dec087e` 仍綁定 spatial_v1，且依回報未開訓。不要修改它的 environment.json、SLX 或課程快照來換版本；日後選擇新環境時建立新 run。

本機不啟動正式訓練；遠端須另建 spatial_v2 run，不能使用先前的 spatial_v1 草稿續訓。遠端由代理提供指令、使用者執行。待本次檔案同步後，可先在遠端專案根目錄的 MATLAB 做唯讀驗證：

```matlab
[manifestFile, assetDir] = trainingenv.registry(pwd,"spatial_v2");
manifest = trainingenv.verify(manifestFile,assetDir);
disp(manifest.id)
disp(manifest.reward_version)
disp(manifest.files.sha256)
```

新 reward 的長期收斂、多 worker／GPU 行為與訓練過關門檻仍待驗證。先前 frozen-policy 的重新計分不能當成新 reward 訓練效果。

## progressive_v2 正式啟動（使用者已指定新版環境）

先確認沒有活動訓練，再於遠端 PowerShell 執行 `git pull --ff-only`。
已保存的舊 run 環境與先前 spatial_v1 草稿不改寫。於 MATLAB 專案根目錄執行：

```matlab
clear retry trainingtools.prepare_progressive_v2_training
rehash
trainingtools.prepare_progressive_v2_training();
cfg=jsondecode(fileread("configs/lab_gpu6_progressive_v2.json"));
assert(strcmp(cfg.environment,"spatial_v2") && ~cfg.start);
args=namedargs2cell(cfg);
newV2=retry(args{:});
[modelFile,manifest]=trainingenv.resolve(newV2.sessionDir);
assert(strcmp(manifest.id,"spatial_v2"));
assert(strcmp(manifest.reward_version,"spatial_reward_v2"));
assert(strcmpi(checkpointreview.sha256(modelFile), ...
    "997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557"));
disp(newV2.sessionDir)
% 以下這一行正式啟動；此前只準備與核對。
info=retry(resume=newV2.sessionDir);
```

只執行一次準備區塊；不要重用之前的 v2.sessionDir 或134932草稿。
用 `training_status(info.sessionDir)` 查看進度。從Stage1、Episode1、新agent開始，
目標6workers、最低1、GPU，實際worker數以日誌為準。
本機已重新通過新版/舊版reward測試、實際SLX公式測試及此課程start=false
環境快照核對；沒有啟動本機正式訓練或驗證遠端GPU收斂。

相關：[離線校準證據](../research/reward-calibration-v2.md)、[環境快照與遠端更新](environment-versions.md)。
