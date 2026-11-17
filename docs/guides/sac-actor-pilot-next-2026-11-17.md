# Actor pilot 後的下一步

目前選擇：保留1600，兩個1700不續訓。來源在本批凍結評估38/40跑滿，基準11/40、半速7/40；兩配方均未保留來源能力。這次指令是短對照的唯讀診斷與交件，不是新的訓練命令。

在遠端 `D:\daniel\ModularTraining` 執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
$ErrorActionPreference = 'Stop'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git 同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -PilotProbe
if ($LASTEXITCODE -ne 0) { throw '診斷未完成，請貼回錯誤；不要啟動 retry。' }
Invoke-Item '.\artifacts\packages'
```

交回 `sac-actor-pilot-probe-*.zip` 與SHA，放本機根目錄即可。不要重傳舊 `sac-actor-pilot-*.zip`。只打包已產出的診斷可加 `-PackageOnly -PilotProbe`，但仍要讀 `review.json` 確認complete。

腳本核對兩臂completed ledger、paused、paper64、來源1600 SHA及當初評估的final SHA。為避免Agent_Final和週期checkpoint序列化差異，只用當初已打包的final模型做1700診斷；來源1600從原run在排他鎖下複製。所有推論在隔離副本，原模型前後SHA核對，保留原pause鎖。三種模式 `-Probe`、`-ActorPilot`、`-PilotProbe` 互斥。

每臂各比較1600/1700的保存狀態、兩段replay共同輸入、16觀測×33動作×雙Q。每臂的第二段replay不同，跨臂不可直接把不同輸入的摘要當策略差；第一段同來源輸入也需核對序列內容。Gaussian值是動作變換前參數，Q不是實測return，不能直接判為高估。沒有正式訓練、飛行模擬、pool或自動調參。

後續訓練決策仍須等診斷能支持可區分的假設。不支持再盲降LR、放寬終止、跳階或無限續訓；若無進一步依據，優先以目前22頁簡報討論任務與控制指標，保留1600作凍結基準。
