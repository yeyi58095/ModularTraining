# ModularTraining

此專案由 Flower 中的 ModularTraining 複製出來，作為獨立專案維護，未來預計上傳 GitHub。執行不需要原 Flower 資料夾。

## 宿舍／實驗室分享精簡紀錄

在產生日誌的電腦執行（只需 Python，不需 matplotlib）：

```powershell
python export_training_report.py "+trainingmodels/ppo_lstm128/runs/實驗資料夾" --machine lab
# 宿舍的實驗改用 --machine dorm
# 放大退步附近的區間：
python export_training_report.py "實驗資料夾" --machine lab --from-episode 170000 --to-episode 190000
```

產生 `reports/<machine>/<session>/report.json`，限制在 1.5 MB 內，可提交 GitHub 後跨機閱讀；完整日誌、checkpoint 與快取由 `.gitignore` 排除。
報告包含 reward／steps／Q0 區間統計、重啟與 worker 摘要、模型設定及程式指紋，不含完整錯誤堆疊。匯出不會啟停訓練或自動 push。
請把範例中的路徑換成實際資料夾；舊實驗可用 `--diagnostics` 明確指定外部診斷目錄。
詳細格式與限制見 [reports/README.md](reports/README.md)；本次架構審視與雙機工作紀錄見 [docs/review-2026-10-09.md](docs/review-2026-10-09.md)。
分享報告不能代替 checkpoint 續訓；複製實驗跨機續訓前需檢查 `control.json` 的 `diagnosticDir` 等路徑。

## 訓練 Reward 圖表

從專案根目錄執行：

```powershell
python -m pip install -r requirements-plot.txt
python plot_training_rewards.py
python plot_training_rewards.py "+trainingmodels/ppo_lstm128/runs/實驗資料夾"
python plot_training_rewards.py "+trainingmodels/ppo_lstm128/runs/實驗資料夾" --watch 60
```

未指定路徑時，依日誌修改時間選擇本專案最新的實驗；也可以指定模型資料夾或其 `runs/`。輸出預設為實驗內的 `reward_history.png` 和 `reward_history.csv`，可用 `--output 路徑.png` 改位置。圖表包含每回合 reward、日誌記錄的平均 reward 與重啟分界；重複 episode 使用較新 attempt 的紀錄。工具只讀取日誌，Ctrl+C 停止圖表更新不影響訓練。

獨立於旁邊 `Simulink/` 的實驗版本。包含自己的訓練腳本、supervisor、checkpoint 輔助檔，以及 FAFA_Simulation.slx 副本；不呼叫舊資料夾內的訓練檔案。
現行 Simulink 版本不需停止或更新。這份程式不會自動啟動、終止或刪除現行實驗。

## 啟動

MATLAB 切換到本資料夾後：

```matlab
runInfo = retry(model="ppo_lstm128", workers=6);
% 另一種架構，建立另一個新實驗：
% runInfo = retry(model="ppo_lstm256", workers=6);
% runInfo = retry(model="ppo_mlp", workers=6, device="cpu");
```

每次新啟動產生 `+trainingmodels/<模型名稱>/runs/<時間_唯一碼>/`。預設使用 GPU、每 100 回合存檔、每 1000 回合重啟程序，最近 50 回合平均 reward >= 2900 時保存 Agent_Success.mat 並結束。
workers 是每段目標，啟動失敗依 `fallbackWorkers=[4 2]` 降級；下一段重新嘗試目標數量。這不保證修復授權問題。

```matlab
runInfo = retry(model="ppo_lstm128",workers=6,fallbackWorkers=[4 2], ...
    checkpointEvery=100,episodesPerProcess=1000,maxNoProgressFailures=3);
type(fullfile(runInfo.sessionDir,'status.json'))
```

`retry(...,start=false)` 只建立設定與模型快照，方便檢查，不啟動背景程序。
返回 PID 只表示 supervisor 已啟動；stdout 出現 Episode 才代表開始訓練。

## 續訓與停止

```matlab
runInfo = retry(resume="D:\完整路徑\ModularTraining\+trainingmodels\ppo_lstm128\runs\實驗資料夾");
% 續訓可以改 worker 數，但沿用同一個模型：
% runInfo = retry(resume="D:\完整路徑\實驗資料夾",workers=4);
fid=fopen(fullfile(runInfo.sessionDir,'STOP'),'w'); fclose(fid);
```

續訓從該實驗最新有效 checkpoint 接續，回合數累計。省略的執行選項沿用 control.json；指定不同模型名稱會拒絕。
舊版 Simulink 實驗沒有 model.json，不能直接交給這個入口續訓；請繼續用舊入口，避免錯配模型。
改架構／神經元數量請建立新實驗。要從頭跑只須再呼叫 `retry(model=...)`，不必刪掉舊資料。

## 模型定義

新增調參版：`ppo_lstm128_tuned_stability_20260923_v1`（2026-09-23）。根據 29000 回合紀錄的後期退步，將 actor learning rate 從 5e-5 降為 2.5e-5、NumEpoch 從 3 降為 2；尚未完成新訓練驗證。依據與啟動方式見該模型資料夾的 `TUNING.md`，成果同樣寫入其 `runs/`。

`+trainingmodels/` 內：

- `ppo_lstm128/ppo_lstm128.m`：原有 PPO 參數與 LSTM 128 架構。
- `ppo_lstm256/ppo_lstm256.m`：LSTM 改為 256。
- `ppo_mlp/ppo_mlp.m`：不含 LSTM 的前饋網路。
- `build_agent.m`：用設定建立 actor、critic、PPO agent。
- `validate_agent.m`：續訓時核對網路與參數。

例如新增 `+trainingmodels/ppo_custom/`，複製一個 profile 成其中的 `ppo_custom.m`，函式名稱及 spec.name 改為 ppo_custom，然後調整：

```matlab
function spec = ppo_custom()
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_custom';
spec.lstmUnits = 256;
spec.actorHidden = [128 64 32];
spec.criticHidden = [128 64];
spec.actorLearnRate = 3e-5;
end
```

之後 `retry(model="ppo_custom")`，不需修改 retry。每個實驗保存 model.json 與 model_source/+trainingmodels 原始碼快照；後來編輯 profile 不會改掉該實驗續訓所用的模型設定／builder。
快照只複製共用與各模型資料夾內的 `.m` 原始碼，不包含 `runs/` 訓練成果。模型定義與輔助函式請放在模型資料夾第一層。
快照不包含整個 runtime，請勿在活動中的此版本訓練期間修改 runtime。新的模組化副本與原 Simulink runtime 則彼此獨立。

目前實際支援 **PPO 的不同網路架構**，環境固定為 FAFA 的 10 維 observation、1 維 action、0.1 秒 sample time。
SAC、TD3 等演算法尚未支援；需要擴充 builder、checkpoint 相容性及訓練選項，不能只改 algorithm 字串。

## 診斷與檔案隔離

```text
ModularTraining/
  retry.m                 對外入口
  training.m              模型與訓練引擎之間的介面
  +trainingmodels/
    build_agent.m         共用的 agent 建立程式
    validate_agent.m      共用的 agent 驗證程式
    load_profile.m        模型定義載入器
    ppo_lstm128/
      ppo_lstm128.m       此模型的定義
      runs/
        <時間_唯一碼>/
          model.json      此次訓練的模型設定
          control.json    此次訓練的執行設定
          model_source/   原始碼快照
          checkpoints/    定期存檔
          Agent_Final.mat 最後存檔（訓練後產生）
          Agent_Success.mat 達標存檔（達標後產生）
          diagnostics/    worker／episode CSV 與診斷日誌
          runs/           各段訓練的詳細紀錄
    ppo_lstm256/
      ppo_lstm256.m
      runs/
    ppo_mlp/
      ppo_mlp.m
      runs/
  runtime/                獨立的重試／訓練引擎、Simulink 模型副本
  sessions/               舊版實驗位置（仍可用完整路徑續訓）
  training_diagnostics/   舊版診斷位置；新實驗位於各次訓練的 diagnostics/
  tests/                  不跑長時間 UAV 訓練的驗證
```

診斷包含 episode_workers.csv、worker_attempts.csv 和各 attempt 的完整日誌。
每段訓練的內層紀錄目錄使用 `runs/r000001/`、`runs/r000002/` 等短名稱，避免 Windows 下 MAT v7.3 存檔因路徑過長而誤報檔案損毀；已存在的紀錄保留。`tests/test_short_run_paths.m` 驗證長路徑錯誤重現、短路徑訓練選項存取及路徑長度檢查。
`ActualWorkers < TargetWorkers` 即為降級回合；被回滾後重跑的回合用 Attempt+Episode 區分。
資料夾隔離不會隔離硬體或 MathWorks 授權資源；同機同時跑新舊訓練仍會共用 RAM/GPU。此入口本身不會動舊程序。

只需要把整個 ModularTraining 資料夾加入 Git 並同步，不需要更動舊 Simulink 資料夾。

## 驗證

`tests/test_model_layout.m`：不啟動訓練，驗證模型分類、每次訓練的獨立路徑、快照排除成果、續訓及舊版診斷路徑相容性。

`tests/test_modular_training.m`：在 R2024b 建立三種 PPO 網路、產生 action、核對架構、準備及續用設定、拒絕不匹配模型，並載入隔離的 SLX。
`tests/test_end_to_end.m`：CPU／1 worker 的單回合真實 UAV 訓練，使用測試專用的低成功門檻，驗證 supervisor、模型快照、checkpoint／成功存檔及 episode CSV；不代表模型已學會任務。
`tests/test_episode_format.ps1`：驗證 MATLAB Episode 行的補空白格式及去重。
未驗證此新副本的遠端 6-worker 長時間訓練或所有自訂架構。
