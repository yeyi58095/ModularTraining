# 弱風子 run 的歷史 checkpoint 批次評估

在遠端 paused 的子 run 20261105_210649_recovery_tpb199bcee 評估 1000:100:1500 六份模型。每份用 516:525 十條已檢視過的診斷路線，stage 1/2、CPU 無探索、每次最多 3000 步，總計 120 次。這是既有 checkpoint 的回溯診斷。

在遠端 PowerShell 同步：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請先停止。' }
```

於新的 MATLAB R2024b 工作階段執行：

```matlab
cd('D:\daniel\ModularTraining'); addpath(pwd); rehash;
bundle = trainingtools.review_sac_wind_history();
disp(bundle);
```

各 checkpoint 執行完後自動接下一個，結果複製到 artifacts/packages/sac-wind-history-20261105_210649_recovery_tpb199bcee。內含六個 episode 資料夾，各有 evaluation.json、scenarios.mat、逐次飛行 MAT 軌跡及檔案 SHA256 清單；最外層為 manifest.json、summary.json 與來源設定。manifest 的 completed_episodes 記錄已完成的 checkpoint。途中中斷可重跑同一函式，核對後略過已完成項目，未完成的 checkpoint 會重新評估。失敗資訊記於 manifest.error。

執行期間可在另一個 PowerShell 查看：

```powershell
$bundle = 'D:\daniel\ModularTraining\artifacts\packages\sac-wind-history-20261105_210649_recovery_tpb199bcee'
Get-Content -Raw -LiteralPath (Join-Path $bundle 'manifest.json') |
    ConvertFrom-Json | Format-List status,completed_episodes,error
```

完成後打包，僅選該交件資料夾，將 ZIP 與 SHA256 一起交回：

```powershell
$ErrorActionPreference = 'Stop'
$bundle = 'D:\daniel\ModularTraining\artifacts\packages\sac-wind-history-20261105_210649_recovery_tpb199bcee'
$manifest = Get-Content -Raw -LiteralPath (Join-Path $bundle 'manifest.json') | ConvertFrom-Json
if ($manifest.status -ne 'complete') { throw '評估尚未全部完成。' }
$zip = $bundle + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip'
if (Test-Path -LiteralPath $zip) { throw 'ZIP 已存在。' }
tar -a -cf $zip -C (Split-Path $bundle -Parent) (Split-Path $bundle -Leaf)
if ($LASTEXITCODE -ne 0) { throw '打包失敗。' }
Get-FileHash -LiteralPath $zip -Algorithm SHA256
```

驗證範圍為 R2024b 假評估器的批次、略過已完成、檔案破壞偵測；實際飛行沿用既有 compare_training_checkpoints。完整 120 次評估由使用者在遠端執行。
