# 路徑首次初始化修正

`runtime/FAFA_Simulation.slx` 的 OBSERVATION/MATLAB Function3 (WindowManager) 原本只在 `mod(buffer_counter, window_length)==0` 發出有效訊號。window_length=100、取樣0.1秒，導致前99次呼叫的planner只有一點路徑，guidance回傳預設零誤差。

修正為：

```matlab
if buffer_counter == 1 || mod(buffer_counter, window_length) == 0
    valid_flag = true;
end
```

此條件仍位於「剩餘點數足夠構成完整window」的分支內，不改輸入長度要求、之後更新週期、reward、終止門檻或agent設定。SLX封裝逐項比較確認只有chart_60.xml的這一行改變，其餘entry內容一致。

## 相容性

這是環境行為改變，不是checkpoint格式變更。舊agent仍可載入，但舊環境的分數與新環境不能直接視為同一測試；evaluation.json的model_sha256會不同。既有curriculum快照、checkpoint、guard狀態均不修改，不自動開始訓練。

實驗室保持paused，更新後先評估：

```matlab
clear compare_training_checkpoints
rehash
evaluation = compare_training_checkpoints(info.sessionDir, ...
    episodes=[10600 10700],includeLatest=false,stages=[1 2 3]);
disp(jsonencode(evaluation.results,PrettyPrint=true))
```

這是目前修正版環境的CPU評估，不是舊環境重現。若FAFA_Simulation已開啟，先確認沒有未存修改；評估工具會拒絕使用已開啟的模型，避免覆寫。

## 驗證

`tests/test_window_startup.m` 由實際SLX載入Stateflow函式並直接執行，確認有效呼叫為[1,100,200]、每次window正確切片，短於window的路徑維持無效。不啟動訓練。

本機使用實驗室傳回的10600／10700，原版與修正版各做一次直線CPU sim，seed101、無探索、上限200步。原版在獨立暫存模型副本執行，四次均驗證來源checkpoint雜湊及actor/critic權重不變。

|Checkpoint|原版步數／reward|修正版步數／reward|
|---|---:|---:|
|10600|200 / 188.5240|200 / 175.3604|
|10700|133（IsDone）/ 116.4940|200 / 145.2127|

原版10700重現實驗室133步結果。修正版10700在200步內未提前終止，不能推論已能完成3000步或修好長期收斂；10600的短段reward沒有上升。兩版初始路徑行為不同，分數變動不單獨代表模型更好。原始A/B結果及MAT保存在本機忽略目錄diagnostic_packages/startup_ab.json及startup_v*_ep*.mat。

初始化缺陷修正不等於已修復PPO學習退步；不能據此解除guard或覆蓋原實驗續訓。調查背景見lab-trace-findings-2026-10-10.md。

## 實驗室3000步上限評估回報

使用者提供 evaluation_20261010_200516_tpa46ecfc4 的完整輸出，六項評估完成（seed101，CPU，確定策略）。10600直線/S彎/固定轉彎步數3000/3000/1578，reward3101.85/3184.58/1387.23；10700步數3000/3000/1589，reward2530.87/2686.42/1413.17。

對照原版10700的133/134/133步，初始化修正消除了這組固定條件下的早期失敗。應修正之前把它概括為舊任務能力完全遺失的說法：相同權重在修正版仍可完成直線/S彎，原版的啟動行為是失敗的重要因素。但10700仍有較低reward，直線/S彎observation7 RMS為0.67378/0.65355，相比10600的0.18496/0.12763高；依已驗證d/30映射，模型路徑誤差RMS約20.21/19.61m對5.55/3.83m。兩者第三階段仍未完成，不能宣稱退步或課程難度問題全部解決。

優先保留10600作為下一次獨立試驗候選，不直接resume暫停分支最新11000。若續訓需建立新run並記錄修正版模型雜湊，保留舊環境資料；本回報不代表已授權啟動訓練。此次新trace尚未傳回本機，不能假設固定轉彎仍由相同終止條件觸發。

## 新實驗配方與 JSON 的位置

使用者後續決定另開實驗。`configs/recovery_startup_fix.json` 指定从第一個 recovery 分支10600接續，要求來源actor LR=2.5e-5、scale=1，不再減半；100回合/段、新增上限1000，保留原guard規則與父control的硬體設定。prepare仍不啟動，正式執行由使用者呼叫retry。

```matlab
clear prepare_recovery_training retry
parentSession = fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261010_155437_recovery_tpebed29a8");
fresh = prepare_recovery_training(parentSession,"configs/recovery_startup_fix.json");
info = retry(resume=fresh.sessionDir);
```

共用課程仍是 experiments/progressive_v1/curriculum.json。新run複製父實驗的curriculum.json和assets快照，從10600所屬stage3接續；curriculum_state.json仍留在新run中，不會寫回共用課程或重跑stage1。這是接續學習的新run，不是新隨機初始化的agent。

新run的control.json繼承硬體、model.json記錄不變學習率、recovery.json記錄來源和準備當下的runtime模型/引擎SHA256。SHA只記錄準備時版本，不是隔離整份runtime；之後仍不得在活動訓練期間更新runtime。沿用歷史時guard亦會參考同stage舊歷史，這是保守停止規則，不是新舊環境分數完全可比的證據。
