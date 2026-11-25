# 歷史診斷包的離線分析

這些入口讀取宿舍端保存的 2026 年 10 月 PPO 診斷與 11 月 SAC 風況交件。MATLAB 從專案根目錄呼叫 `trainingtools.historical`。讀取 agent 或 Simulink traces 時，使用 MATLAB R2024b 與對應的 Reinforcement Learning／Simulink 工具箱。Python 工具需要 NumPy。

MATLAB 有檔案輸出的入口會回傳當次新建的目錄，位置為 `artifacts/historical-diagnostics/<入口>/<唯一目錄>/`。原始 MAT、checkpoint、ZIP、圖與完整匯出陣列留在本機。換機重算時，先把相對應的原始資料放回下表的位置。

| 分析 | MATLAB 入口（前綴 `trainingtools.historical.`） | 本機輸入（相對於 `diagnostic_packages/`） |
| --- | --- | --- |
| Stage 5 逐次觀測、動作及場景 | `inspect_stage5()` | `stage5_21600/` |
| Stage 5 訊號名稱、型別及完整追蹤資料 | `inspect_detail()`、`export_detail()` | `stage5_detailed/` |
| Stage 5 候選組的六份詳細資料、單獨 seed 207 | `export_candidate()`、`export_candidate_small()` | `stage5_candidate/` |
| Stage 6 原版 MAT 匯出、候選失敗樣本、有限原路線距離 | `export_stage6()`、`export_history_failures()`、`check_progress_geometry()` | `stage6_review/main/reports/`，候選匯出另需 `stage6_review/history_review_receipt.json` |
| 恢復時的權重、公開選項及 worker seeds；critic 初值對記錄報酬 | `inspect_recovery_resume()`、`inspect_recovery_critic()` | `recovery_review_20261016/` 的 checkpoint、初始快照、訓練選項及評估 traces |
| 探索開關與 actor 在相同觀測的輸出 | `inspect_exploration_pair()` | `exploration_pair_20261016/` 與 `recovery_review_20261016/checkpoints/` |
| 相同歷史觀測重播不同 checkpoint | `replay_actors("lab")`、`replay_actors("recovery")`、`replay_actors("regression")` | 依序為 `lab_recovery_e44b46f8/`、`recovery_review_20261016/`、`regression_models_20261016/` 加 `regression_20261016/` |
| 退步段數值與前 12 秒軌跡圖 | `export_regression()`、`plot_regression()` | `regression_20261016/` |
| 恢復配方、guard 與記憶體內的學習率變更稽核 | `check_recovery_v2_recipe()` | `regression_models_20261016/checkpoints/Agent18400.mat`，以及倉庫內的 `recovery_v2_18000_guarded.json` 與 spatial_v2 環境 |

從新匯出的陣列畫圖，或重算兩份 SAC checkpoint 的配對摘要：

```matlab
arraysDir = trainingtools.historical.export_regression();
plotDir = trainingtools.historical.plot_regression(fullfile(arraysDir,'arrays.json'));
windDir = trainingtools.historical.review_wind_traces();
```

SAC 入口讀取 `artifacts/incoming/sac-wind-history-20261106/sac-wind-history-20261105_210649_recovery_tpb199bcee/` 中兩份 checkpoint 的評估 traces。可傳入其他位置的同一份交件。它重算 E1300／E1400 在 Stage 1、2、種子 516–525 的共同步數與前 100 步後的統計。語義見[原始研究紀錄](../records/sac-wind-trace-review-2026-11-06.md)。

從專案根目錄對已匯出的 Stage 6 E31600 四個失敗樣本重算幾何量：

```powershell
python .\tools\historical\analyze_stage6.py
```

預設讀取 `diagnostic_packages/stage6_review/ep31600_stage6_seed*.json`，可透過 `--input-dir` 指向 `export_stage6()` 產生的新目錄。保存當時的[離線分析原稿](../records/stage6-offline-findings-2026-10-13.md)及後續的[隔離評估紀錄](../records/stage6-history-review-2026-10-13.md)，兩者的測試範圍不同。

## 10 月 10 日固定策略的啟動 A/B

[compare_startup_models.m](../../+trainingtools/+historical/compare_startup_models.m) 讀取 `lab_recovery_e44b46f8/checkpoints/Agent10600.mat`、`Agent10700.mat` 與 `reports/evaluation_20261010_183235_tp0d559eeb/scenarios.mat` 的第一組直線。四趟均在 CPU 關探索，以種子 101、零風、200 步上限比較首次路徑初始化修正前後的行為。模型從已核對雜湊的輸入複製到當次輸出目錄。不同 checkout 的現行 runtime 可能已經歷後續模型修改。

兩個原始模型的 Git 物件都在本倉庫歷史內。缺少副本時，可在專案根目錄以 PowerShell 執行以下指令。存在的檔案保留，MATLAB 入口會在模擬前核對兩個 SHA-256。

```powershell
@'
from pathlib import Path
import subprocess
root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
bundle = root / "diagnostic_packages"
bundle.mkdir(exist_ok=True)
for name, revision in [
    ("before", "a729ca07c6f2f091093e1af1305ac4c8289ffd59"),
    ("after", "8f0bef2010ebf8df26f97dd8ed17492280d1a63c"),
]:
    target = bundle / f"FAFA_Simulation_{name}_startup_fix.slx"
    if not target.exists():
        model = subprocess.check_output(["git", "-C", str(root), "show", revision + ":runtime/FAFA_Simulation.slx"])
        with target.open("xb") as output:
            output.write(model)
'@ | python -
```

MATLAB 入口為 `outputDir = trainingtools.historical.compare_startup_models();`。也可傳入兩個已保存的本機模型路徑。當次的四個 MAT 與 `startup_ab.json` 會輸出到新的結果目錄。[當時的結果與取樣範圍](startup-path-fix.md)

## 10 月 13 日 Stage 6 的 valid_history 配對方法

宿舍原始 `stage6_review/run_history_review.m` 的三組設定如下。重現對象為歷史模型與單一 E31600 checkpoint。完整的兩包 ZIP 雜湊見[當時的稽核紀錄](../records/stage6-history-review-2026-10-13.md)。

1. 在獨立、可丟棄的 checkout 準備歷史評估程式。版本 `fbc1032ec1111ba6aed02c4e1839e5239ebb6db2` 包含 `valid_history` 實作。僅在這份 checkout 的 `runtime/FAFA_Simulation.slx` 使用 Git 物件 `e4d27549a30516bee58f30734608f3c9cbb03dbb:runtime/FAFA_Simulation.slx`，其 SHA-256 為 `b28c5a5c967347c498cb23f032b483841ca63b98ab4da137ca902e193225714c`。這是供重建的已知程式組合。當時收據另列 runtime、課程與 random path 的 SHA，可逐一比對。
2. 將唯讀的 `stage6_review/main/` 診斷包複製到該 checkout 的全新 `artifacts/` 子目錄，令 `session` 指向新副本。確認複製的 `checkpoints/Agent31600.mat` SHA-256 為 `75bc17b133c86c974b11ebfbb23be385e9965605323486b2ff36891626c8e823`。
3. 從補充包 `extra/evaluation_20261013_185622_tp1a1a8597/scenarios.mat` 讀取 `scenarios`。僅在新副本缺少 `curriculum_assets/stage001.mat` 或 `stage002.mat` 時，分別保存 `scenarios{i,1}.waypoints` 和 `scenarios{i,1}.velocity` 為同名變數。原始腳本在新副本缺少 `supervisor.lock` 時建立空檔，供唯讀評估取得獨占鎖。既有 run、鎖與來源包保留原位。
4. 在該隔離 checkout 的 MATLAB R2024b 工作階段，以 CPU、關探索、每趟 3,000 步上限執行三組呼叫。共 4 趟 baseline、20 趟候選、3 趟保留性評估。

```matlab
baseline = compare_training_checkpoints(session, episodes=31600, includeLatest=false, ...
    maxSteps=3000, stages=6, seeds=[202 204 205 207], diagnostics=true);
candidate = compare_training_checkpoints(session, episodes=31600, includeLatest=false, ...
    maxSteps=3000, stages=[5 6], seeds=201:210, diagnostics=true, guidanceVariant="valid_history");
retention = compare_training_checkpoints(session, episodes=31600, includeLatest=false, ...
    maxSteps=3000, stages=[1 2 3], seeds=101, guidanceVariant="valid_history");
```

當時的 `history_review_receipt.mat` 保存三份回傳值，JSON 收據對應 `baseline.outputDir`、`candidate.outputDir`、`retention.outputDir`。重算時把新收據保存在隔離目錄，並在三組結束後複核來源 SLX 與 checkpoint SHA。
