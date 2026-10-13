# Stage 6：按飛機進度提供前方路段

使用者於 2026-10-13 明確選擇「沿指定路徑穩定飛行，可依飛機進度更新路段」。本版本是空間循跡環境，不是原本按時間推進 15 m/s 的移動目標追蹤。歷史 Stage 完成紀錄保留，但不能當作新環境已完成整套資格驗證。

## 修正範圍

- guidance 的歷史路徑只取有效的 `path_length`，避免未填入的零列形成通往原點的虛假線段。
- WindowManager 用目前位置在局部路段上的最近 waypoint 更新單調前進的索引，不再每個取樣無條件前進一點。搜尋限於目前索引往前一個 window，避免任意跳到整條路線的遠端。
- 目前 window 為 100 點、間隔 1.5 m。在距離段尾約 40 個 waypoint 時，提早提供下一段連續的 100 點；新舊段共享端點，讓規劃器原有 `last_point` 接段方式保持連續。第一個重疊 window 候選會退步，沒有部署。
- 不更動 reward 公式、50 m 終止門檻、動作範圍或 PPO 學習率。但誤差幾何與路徑更新環境改變，前後 reward 不能全解讀為 agent 學習改善。
- 此版本不提供按原時序移動的目標或原 loiter 行為。僅發送完整路段；末尾不足一段時保留最後有效路段。3000 步完成不等於到達整條軌跡終點。

## 實驗室續訓

先確認原實驗仍為 paused，且沒有評估／訓練使用這份 runtime。PowerShell：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
```

MATLAB（只準備一次新分支）：

```matlab
cd D:\daniel\ModularTraining
clear prepare_recovery_training retry
rehash
if bdIsLoaded('FAFA_Simulation'), close_system('FAFA_Simulation',0); end
root=fileparts(which('retry'));
parentSession=fullfile(root,'experiments','progressive_v1','runs', ...
    '20261012_080431_recovery_tpfaf0be04');
next=prepare_recovery_training(parentSession, ...
    fullfile(root,'configs','recovery_31600_progress_window.json'));
info=retry(resume=next.sessionDir);
disp(info.sessionDir)
```

從 Agent31600 開始，沿用 Stage 6 位置及 actor LR 2.5e-5，每段 100 回合，最多新增 10000 回合至 41600。課程達標或 guard 觸發可以提前停止。硬體沿父 control（目標 6 workers、GPU；以實際 pool_ready 為準）。配方核對正式 SLX SHA，避免只複製 JSON 卻使用舊模型。

新分支保留繼承來源；不刪除原 guard，不覆盖父 checkpoint。診斷 ZIP 子集不可拿來直接續訓。此指令應在保存完整父實驗的實驗室執行。

## 進度與後續驗收

```matlab
s=jsondecode(fileread(fullfile(info.sessionDir,'status.json'))); disp(s)
type(fullfile(info.sessionDir,'curriculum_state.json'))
f=fullfile(info.sessionDir,sprintf('attempt_%05d',s.attempt),'stdout.log');
if isfile(f), t=splitlines(string(fileread(f))); disp(join(t(max(1,numel(t)-29):end),newline)); end
```

Stage 6 從 22400 起算；最低 10000 回合最早在 32400 到達，還必須同時滿足原有連續窗口 reward / 完成率條件。不要只憑本次純模擬通過便稱模型合格；續訓完成後仍需保存新 checkpoint，再做所有階段與新情境評估。若 `suspected_regression` 暫停，保持暫停，不直接解除。

正式環境評估使用 `guidanceVariant="baseline"`，表示當下正式 SLX。候選转换函式拒絕重複套用；舊版來源 fixture 僅供測試。結果與限制見 [驗證紀錄](../records/stage6-progress-validation-2026-10-13.md)。
