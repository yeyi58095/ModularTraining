# 凍結模型的探索開關對照

`compare_training_checkpoints(..., useExploration=true)` 在CPU純sim中啟用已儲存PPO的動作抽樣。預設false維持原評估行為。兩者皆不train、不改checkpoint、不解除guard；報告`use_exploration`明確記錄模式，保留權重與SHA檢查。

相同stage/seed先生成相同scenario；模擬前重設同一seed。探索模式的軌跡會因動作不同而改變。這不是重現並行訓練worker的完整隨機狀態，也不能由開關對照單獨證明崩落根因。

實驗室恢復分支20261016_162607_recovery_tpf699ae87已有18000/18100/18200、stage4、seed601:606的關閉探索評估：reports/evaluation_20261016_194120_tpd47c04a4/evaluation.json。更新評估工具後只需同組開啟探索再評估18次，無須重跑原組：

```matlab
session=fullfile(pwd,"experiments","progressive_v2","runs", ...
    "20261016_162607_recovery_tpf699ae87");
exploreReview=compare_training_checkpoints(session, ...
    episodes=[18000 18100 18200],includeLatest=false, ...
    stages=4,seeds=601:606,useExploration=true,routeMetrics=true);
disp(jsonencode(exploreReview.summary,PrettyPrint=true))
```

若只有探索組大量失敗，證明這批固定策略對動作抽樣敏感，不證明探索是訓練更新失控的唯一原因；若探索組也全跑滿，應優先調查更新過程、訓練路徑分佈與並行狀態差異。不要直接關閉PPO訓練探索或放寬過關條件。六seed屬診斷而非泛化認證。

整合測試test_checkpoint_exploration接收既有checkpoint路徑，在獨立未訓練run做三次五步CPU模擬；檢查預設模式、探索模式動作不同、相同seed探索重播、配對scenario及checkpoint/權重未變。不代表GPU或正式訓練驗證。

## 評估專用標準差縮放

`useExploration=true, explorationStdScale=0.5` 將Gaussian actor的std輸出乘0.5（variance為原本0.25），保留原本均值分支與所有可學權重。只對記憶體中的actor新增無可學參數的scaling layer，不修改SLX、reward、checkpoint或訓練超參數，不另存可續訓agent。預設scale=1保持原行為；禁止scale<=0、>1或未開啟探索時縮放，避免混淆評估條件。

相同觀測歷史下均值不變；閉迴路觀測因動作不同而改變時，後續均值仍可能跟著改變，不能宣稱整段飛行的均值序列固定。此功能只支援本專案observation/mp_out/sdev命名的Gaussian actor。

實驗室以18000/18100/18200、stage4、seed601:606執行同組18次，與既有scale=1及關閉探索報告比較。這是單一預設候選，不反覆調到seed601過關；通過仍不證明訓練穩定、所有隨機路徑合格或根因已修復。

```matlab
scaledReview=compare_training_checkpoints(session, ...
    episodes=[18000 18100 18200],includeLatest=false, ...
    stages=4,seeds=601:606,useExploration=true, ...
    explorationStdScale=0.5,routeMetrics=true);
disp(jsonencode(scaledReview.summary,PrettyPrint=true))
```

報告記錄exploration_std_scale；舊報告缺此欄位表示當時原始actor未縮放，不修改既有報告。test_exploration_scale以既有觀測驗證均值不變、std精確減半、可學權重不變，並檢查短CPU模擬與seed重現性；不驗證正式訓練。
