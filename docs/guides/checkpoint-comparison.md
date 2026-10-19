# 停訓後比較 checkpoint

`compare_training_checkpoints` 使用 `sim`，不呼叫 `train`、不回滾、不改寫課程狀態或 MAT checkpoint。先評估再決定是否續訓；另開分支使用 trainingtools.prepare_recovery_training。

## 實驗室操作

確認原實驗 stopped，於 PowerShell 更新：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
```

在 MATLAB 專案根目錄執行（FAFA_Simulation 必須未開啟；建議另開乾淨 MATLAB）：

```matlab
sessionDir = fullfile(pwd,"experiments","progressive_v1","runs","20261009_201547_tpf1292058_f8ca_4ccd_bc7f_a66b20ee91b4");
evaluation = compare_training_checkpoints(sessionDir);
disp(jsonencode(evaluation.results,PrettyPrint=true))
```

預設比較 6100、10600 與最新 checkpoint，各在課程快照前三階段評估一次，最多各 3000 步。若最新與前兩個重複則去重。checkpoint 的 episode 以已保存訓練歷史驗證；最新候選不可讀時明確報錯，不偷偷改用較舊模型。

使用 CPU、單程序，不啟動 worker pool，不更改正式 GPU／6 workers 設定。明確關閉策略探索，各次 sim 重載 agent；相同 seed、相同保存軌跡、模型初始條件與零風。以上為預設前三階段；2026-10-11 新增 random 與風場評估，使用方式及配對 seed、終端門檻證據的限制見 [Stage 5 診斷](stage5-evaluation.md)。

## 結果

每次建立新的 `run/reports/evaluation_<時間>_<唯一碼>/`，內含：

- `evaluation.json`：checkpoint 路徑／episode／SHA256、目前 runtime／SLX／課程指紋、每次 reward、步數、IsDone、動作飽和比例等。可貼回對話；目前整個 evaluation 目錄受 Git 忽略，不使用 `git add -f` 上傳。
- `scenarios.mat`：本次實際使用的固定軌跡與選項。
- `ep*_stage*_seed*.mat`：原始 observation/action/reward/IsDone experience，留在實驗室。

逐次保存結果；`status=complete` 才表示整組成功。失敗會記錄 failed 與錯誤，不能把部分完成當全組比較。Ctrl+C 可以停止評估，不會動訓練存檔；中斷時 JSON 可能仍為 running，已保存列可讀取但不是完整結果。編譯快取放在系統暫存目錄，避免 Windows 深層路徑限制；路徑會寫入 JSON。

`reached_step_limit` 只表示跑到本次設定上限，不保證路徑完成或控制正確。`environment_done` 只代表模型的 IsDone；termination_evidence 新增終端 observation 門檻證據，並非直接記錄 IsDone 分支，不能推論失速；詳見 Stage 5 診斷文件。`observation7_rms` 是原始 observation 第 7 通道統計，不宣稱為公尺單位追蹤誤差。

這是已訓練任務的固定條件診斷，不是獨立泛化測試。預設只有一個 seed；即使指定多個 seed，固定初始狀態／零風／確定策略也可能完全重複，不代表多個獨立測試情境。不能從此結果宣稱統計成功率。

## 保護與驗證

工具取得既有 supervisor.lock 排他鎖並檢查停止狀態；不呼叫會更新狀態的 trainingcurriculum.prepare。要求模型未開啟，不操作其他 pool。結束後還原 cwd、path、rng、原 Agent_Stage2、軌跡 globals 與 Simulink 快取設定；模型關閉但不存檔。checkpoint 比較前後比對 SHA256，sim 前後比對 actor／critic 權重。

固定路徑與模型設定輔助程式取自目前 training_engine，避免更動活動訓練的程式；每次評估檢查固定路徑函式與引擎版本一致，若後續修改造成差異則拒絕執行。這仍是「目前執行版本」的評估，不能證明它與歷史訓練 runtime 完全相同。

測試入口：`tests/test_checkpoint_comparison_guards.m`（不模擬）；`tests/test_checkpoint_comparison.m`（使用既有本機短測 checkpoint，六次各五步 CPU 真實模擬，不訓練）。

2026-10-10 驗證：初次短測發現深層快取觸發 Windows 路徑限制，已改為系統暫存短路徑。通過真實模擬的範圍是本機既有短測 checkpoint，不是實驗室 6100／10600，也沒有測 GPU／多 worker 或長期收斂。
