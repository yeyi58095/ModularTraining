# 33700 / 41600 額外情境比較

先前45次評估全部跑滿，Stage6十組平均reward為33700最高，但不能宣稱已合格。
保持訓練暫停，更新Git後在MATLAB根目錄執行：

```matlab
clear compare_training_checkpoints trainingtools.review_stage6_candidates
rehash
session=fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261014_000404_recovery_tp3b623159");
batch=trainingtools.review_stage6_candidates(session);
disp(batch.summaryZip)
```

預先指定seeds401:420，Stage4/5/6各40次，共120次CPU純模擬；相同seed對應
相同路徑，按各階段風場規則設定風。不是額外訓練，無自動選擇模型或修改過關條件。
內部turbulence seeds仍固定，不宣稱120個獨立噪音實驗或完整泛化驗證。

新增 `routeMetrics=true` 僅在暫存SLX記錄東/北位置，避免完整planner訊號的大量檔案。
每條result的route_metrics是位置到原始路線**有限線段**的最近水平距離（公尺），
由幾何獨立計算，不使用guidance_d或reward倒推。
同時提供所有樣本及t>=10秒的RMS、最大值、nearest-rank P95、10m內樣本比例。
保留起始位置偏差，不把前10秒排除後的值冒充全程結果。10m只是描述性指標，
尚未訂為通過門檻；最近線段距離在路線交叉時可能對應其他路段，不證明沿路線
單調前進、整條路線完成或高度控制合格。提早終止的短軌跡也可能RMS很低，必須
與steps/environment_done一起判讀。空的10秒後區間在JSON中數值為null，不是0。

完成後分享顯示的Summary ZIP（只有JSON），完整MAT保留在實驗室。每個階段
完成即保存結果；若出錯，貼錯誤與batch.json，勿立刻重跑整批。新種子結果也
只是比較證據，需先討論明確物理驗收要求才能宣布合格。

本機驗證：有限線段端點、重複路點與10秒區間的合成測試通過；實驗室提供的
31600 checkpoint 在Stage6 seed401完成20步CPU純sim，位置記錄、幾何指標及JSON
寫出成功，checkpoint與權重通過評估器不變檢查。這不代替33700/41600的完整
120次實驗室評估，也不是訓練收斂或完整路程驗證。
