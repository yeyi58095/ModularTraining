# 實驗室啟動：6 workers 上限＋GPU

本機已通過 CPU／1 worker 的三階段真實短測，詳見 `validation-2026-10-09.md`。本設定的 GPU、多 worker、六階段長訓練尚未實測，收斂與門檻仍待校準。本次僅準備設定，不在本機啟動訓練。

## 更新程式

確認實驗室這份專案沒有活動訓練後，在專案根目錄的終端機執行：

```powershell
git pull --ff-only
```

MATLAB 的 Current Folder 切到這份 ModularTraining 根目錄。以下所有相對路徑均以此為基準，不使用宿舍的絕對路徑。

## 新實驗：直接啟動

```matlab
prepare_progressive_training();
cfg = jsondecode(fileread("configs/lab_gpu6.json"));
args = namedargs2cell(cfg);
info = retry(args{:});
disp(info.sessionDir)
```

第一行生成直線與 S 彎 MAT，後面讀取 JSON 並正式啟動背景 supervisor。請記下印出的 sessionDir；重複執行這段會建立另一個新實驗，並非續訓。MATLAB 返回提示符不代表背景訓練已結束。

如要先檢查設定而不訓練，將上方 `info = retry(args{:});` 改為：

```matlab
info = retry(args{:}, start=false);
% 檢查該 sessionDir 的 control.json、model.json、curriculum.json 後啟動：
info = retry(resume=info.sessionDir);
```

## 設定含義

- `configs/lab_gpu6.json` 是 retry 的執行參數；`curricula/progressive_v1.json` 定義六階段路徑、風場與過關條件。分開保留，方便兩台電腦用不同硬體執行同一課程。
- `workers:6`、`minWorkers:1`：最多 6 個 MATLAB workers，當次成功取得 n 個便使用 n 個，符合先前的可用數量策略。若整個 pool 建立失敗，後續 attempt 可用 4、2、1 作備援。不是強制湊滿 6 才開始。
- `device:"gpu"`：模型使用 GPU；不代表需要或分配了 6 張 GPU，也不保證比 CPU 快。本設定不會自動改成 CPU。遠端需具備相容 GPU、驅動與相應 MATLAB 工具箱／授權。
- 每 100 回合存 checkpoint，每段最多 1,000 回合後重啟 MATLAB 並評估階段條件。階段預算不足 1,000 時會縮短該段。
- `maxAttempts:0` 不限制總 attempt 數；各階段仍有自己的回合上限，未過關會暫停。連續沒有進展的失敗限制為 3；不要把重試機制當成退步自動修正。

若明確想要求「必須正好 6 個」，請同時設定 `minWorkers:6`、`fallbackWorkers:[]`；這會放棄可用 n 個就先跑的策略。

## 查看、停止與續訓

```matlab
status = jsondecode(fileread(fullfile(info.sessionDir,"status.json")))
```

attempt 的 `pool_ready.json` 記錄實際 workers；`control.json` 的 trainingDevice 應為 gpu。遇到 GPU 或建池錯誤，查該 attempt 的 stdout.log／stderr.log。

需要停止時，使用專案既有 STOP 機制：

```matlab
fid = fopen(fullfile(info.sessionDir,"STOP"),"w");
assert(fid ~= -1); fclose(fid);
```

STOP 可能中斷尚未存檔的回合，保留可用 checkpoint；確認 status 顯示停止且原 supervisor 已退出後才續訓。下一次 MATLAB 開啟後，使用原 sessionDir 的完整路徑：

```matlab
info = retry(resume="此處換成原實驗資料夾完整路徑");
```

續訓讀取原 control.json（包含 GPU／worker 設定）與課程快照；不重新讀 configs/lab_gpu6.json。若因階段預算用盡而暫停，應先檢查報告與門檻，單純續訓不會自動增加預算。

分享精簡診斷，在終端機執行：

```powershell
python export_training_report.py "此處換成實驗資料夾完整路徑" --machine lab
```

完整日誌與 MAT 留在實驗室，僅 reports 下的指定 report.json 可納入 Git。訓練流程與尚未實作的獨立評估／退步回滾見 `training-plan-v1.md`。
