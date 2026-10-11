# 路徑末端 lookahead：只供評估的候選

詳細 traces 證據見 [Stage 5 調查](stage5-trace-findings-2026-10-11.md)。205/207 有風地速約16.3–16.4m/s，超過當前規劃路徑末端後，目標仍停留舊末點，更新時才跳回前方。此候選測試「末端目標不足」對失敗的貢獻，尚未證實能解決所有問題。

`guidanceVariant="endpoint_lookahead"` 僅在臨時模型副本修改 guidance chart：原 inside-window 分支若選到path末點，沿末段切線延伸目標，使沿切線到目標的剩餘距離至少50m。保留原 d/reward/IsDone、planner、更新週期、agent及學習參數。沒有更新正式 SLX。baseline 仍為預設。

限制：延長線不保證與未來轉彎路徑一致，也不保證位於機頭前方；這是局部候選，不是通用路徑規劃解法。原 outside-window 分支不變。只可做模擬診斷；不能因候選回合數增加就宣稱模型學得更好或課程合格。

實驗室保持暫停並更新程式後，模型關閉時執行：

```matlab
clear compare_training_checkpoints
rehash
root=fileparts(which("compare_training_checkpoints"));
session=fullfile(root,"experiments","progressive_v1","runs", ...
    "20261010_224522_recovery_tpc1c4f06e");
candidate=compare_training_checkpoints(session,episodes=21600,includeLatest=false, ...
    stages=[4 5],seeds=[205 207 210],diagnostics=true, ...
    guidanceVariant="endpoint_lookahead");
disp(candidate.outputDir)
disp(jsonencode(candidate.results,PrettyPrint=true))
```

與既有 baseline `evaluation_20261011_210201_tp3d1c0564` 比較：205/207無風皆3000，有風1042/743；210兩者皆3000。使用相同checkpoint、路徑seed及風參數，六次最多各3000步。檢查失敗改善、成功案例有無退步，以及實際幾何而非僅reward。後續需擴展其他seed及前三階段；不能只針對205/207調到通過。

輸出包含 guidance_variant、candidate_guidance.m 及其SHA256，model_sha256仍代表未修改的來源SLX，不代表記憶體中候選版本。trace保留diagnostics，壓縮整個新evaluation目錄分享。舊報告及訓練狀態不改。

本機純函式測試包含越過端點、接近端點和非末端目標；另用既有短測agent做110步CPU純模擬檢查整合，原SLX雜湊必須不變。本機尚無21600 checkpoint，沒有替代實驗室完整A/B驗證。

2026-10-11 上述測試已通過：越過直線終點時原目標100、候選160；接近終點且側偏10m時候選目標140，d仍為10；非末端情境輸出相同。候選模型完成110步真實CPU純模擬且來源SLX SHA不變。短測未重現實驗室失敗，不能視為修正效果驗證。
