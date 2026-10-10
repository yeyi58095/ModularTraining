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
