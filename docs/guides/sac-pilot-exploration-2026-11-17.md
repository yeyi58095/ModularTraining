# SAC pilot 探索開／關比較

目的：區分抽樣策略與關探索策略的飛行差異，最多新增24次CPU純sim，沒有train、pool、retry、換stage或自動調參。模型固定為已核驗的1600／基準1700／半速1700，重用前次關探索結果。這是失敗情境的診斷實驗，不是新訓練指令。

遠端PowerShell：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$ErrorActionPreference = 'Stop'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ExplorationCheck
if ($LASTEXITCODE -ne 0) { throw '比較未完成，請貼回錯誤；不要 retry 或刪除 review.json。' }
Invoke-Item '.\artifacts\packages'
```

完成後交回新 `sac-pilot-exploration-*.zip` 及SHA，放本機根目錄。ZIP含protocol、逐情境off/on comparison、RESULTS.md摘要、前次off評估及新on軌跡。`review.status=complete`表示比較完成，不表示策略過關。

若中斷或報錯，已開始的模擬不會自動重跑；保留ledger，先回傳錯誤。需要打包目前部分結果時：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ExplorationCheck -PackageOnly
```

這項工作要跑Simulink，會比前次純網路推論久；無可靠遠端耗時估計。會顯示 `Evaluating episode ... / stage / seed ...`，三個模型各八次。其餘訓練保持paused，不在另一份副本同時續訓。腳本只對目前副本解析run路徑，不沿用跨機絕對路徑。

具體證據、選seed理由及判讀限制見 [失敗軌跡分析](../records/sac-pilot-failure-traces-2026-11-17.md)。無論結果如何，都不自動續訓或放寬原升階標準。
