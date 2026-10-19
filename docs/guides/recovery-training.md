# 從已驗證候選模型準備恢復試驗

2026-10-10 實驗室固定條件評估：6100／10600 都在直線與平緩 S 彎達 3000 步；固定轉彎分別為 399／1578 步。12600 三條路徑均在 138 步 IsDone。10600 因而是這三個候選中的恢復起點，並非全歷史最佳或已證明泛化成功。

## 實驗室操作

原實驗保持停止，PowerShell 更新程式：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
```

MATLAB 在專案根目錄執行以下「準備」命令，尚不會訓練：

```matlab
parentSession = fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261009_201547_tpf1292058_f8ca_4ccd_bc7f_a66b20ee91b4");
recovery = trainingtools.prepare_recovery_training(parentSession);
```

它會在同課程的 runs/ 下建立一個新 `_recovery_` 實驗；讀取父實驗 Agent10600 的真實歷史，依已記錄分界重建當時階段。完整保留該 checkpoint 的 actor／critic 權重與截至 10600 的訓練歷史，只將記憶體內 agent 的 actor learning rate 乘 0.5，再另存新實驗。同步改新 model.json 以通過續訓 validator，不修改父 MAT 或原課程／model_source。GPU、workers=6、minWorkers=1、fallback 等硬體設定沿用父 control。

新 recovery.json 記錄父路徑、SHA256、episode、學習率前後數值與配方。可核對輸出應為 parentEpisode=10600、stageIndex=3、actorLearnRate=2.5e-5、maxAdditionalEpisodes=1000。來源若與預期不同，先查明再啟動。

確認後，正式啟動**新實驗**：

```matlab
info = retry(resume=recovery.sessionDir);
```

這行才啟動實驗室訓練；預期從 10601 接續。不要對 parentSession 執行 resume。重新開 MATLAB 後 recovery 變數不在，需使用準備時顯示的完整新 sessionDir；不必再執行 prepare 以免多建一份。

## JSON 決定的動作

配方：`configs/recovery_actor_half.json`。新實驗保存獨立 `training_guard.json`，不因後續編輯共用配方而改變。

- 每段 100 回合；同階段每 100 回合形成不重疊區間。
- 參考區間必須平均 reward >=500、平均步數 >=500，選其中 reward 最高者，步數以同一區間為準。
- 連續 3 個完整區間，reward 和步數都低於參考的 50%，標記 suspected_regression，在保存後暫停。
- 從父 checkpoint 起最多新增 1000 回合；最後一段會被剩餘預算截短。預設最多到 11600，亦可能因退步、課程條件或程序故障提早停止。
- 檢查在開始 attempt 前及段末 Agent_Final 完成保存後執行。新階段使用新階段歷史，避免直接把換難路徑當成退步。固定路徑尚未學好但一直低於最低參考值時不會觸發比例規則，因此另有總預算。
- `training_guard_state.json` 記錄門檻判定、參考區間、連續低分次數及暫停原因。觸發後保持 paused；單純再呼叫 retry 不會繞過它。後續另建有來源紀錄的新試驗，勿刪狀態檔冒充解鎖。
- 遇到段末恰好是參考最佳區間時，在 health_candidates/ 保留 CandidateN.mat。它只是 training-window candidate，不能標為最佳評估模型，也不會被 supervisor 自動拿去回滾。

這是「規則自動監控與保存後暫停」，不是自動診斷失敗原因。獨立 sim 評估仍由 compare_training_checkpoints 執行；目前沒有自動選最佳評估模型、連續改參數或自動重啟恢復分支。因此沒有無限自動回滾迴圈。

條件是待校準的工程保護規則，可能誤暫停，也不能阻止每次策略退步。只在存檔邊界判斷；不承諾中途每個 episode 即時停止。學習率減半是試驗假設，不是已證實的修復；分段從 1000 改 100 亦改變重啟頻率與 attempt seed，不能把後續差異全歸因於 learning rate。

## 停止後比較

在新實驗 stopped／paused 後執行：

```matlab
evaluation = compare_training_checkpoints(recovery.sessionDir,episodes=10600);
disp(jsonencode(evaluation.results,PrettyPrint=true))
```

這會比較新分支的起點 10600 和最新存檔，不要求新分支存在 6100。新分支沒有複製父 stdout 日誌；畫圖顯示新生成的回合資料，父訓練歷史則保存在 MAT 與 recovery.json 來源紀錄。

## 驗證與保留

tests/test_recovery_guard.m 使用合成退步歷史、既有 CPU 短測 checkpoint 及假引擎，驗證窗口、階段隔離、單指標下降不觸發、復原後重置、權重與父檔不變、learning rate／manifest 一致、剩餘預算截短、暫停後重啟不進訓練。既有課程測試同步通過。未執行正式恢復訓練或 GPU／6 workers 測試。

建立分支失敗時保留 `.preparing` 目錄供診斷，retry 拒絕啟動該目錄。所有 MAT、來源 lineage、規則狀態和日誌依原 .gitignore 留在產生資料的電腦；GitHub 程式碼不是 checkpoint 備份。
