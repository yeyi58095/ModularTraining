# 1600／1700內部狀態與共同輸入診斷

11/16回溯定位新child的1600→1700已退步後，先做唯讀診斷，不直接延長2100或重開同配方500回合。來源固定 `20261114_211021_recovery_tp4c32126b`，需保持paused且已完成前一輪child history。保留1600作為未來候選來源；尚未選定下一輪訓練調整。

遠端無活動訓練時在PowerShell執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -Probe
```

此命令不訓練、不sim、不開workers，不改LR／課程／guard。CPU讀取1600及1700：

1. 既有`inspect_sac_checkpoint`比較alpha、optimizer保存狀態、網路有限值、critic/target距離及近期replay統計。
2. 從兩checkpoint的近期replay各取最後一個有完整terminal邊界episode的最多256步prefix，讓兩模型使用完全相同輸入，比較Gaussian mean/std與對記錄動作的雙Q。
3. 在第一份prefix的最多16個固定觀測上，掃描33個[-1,1]動作，保存兩模型的雙Q動作曲線。

各子工具取得來源run排他鎖、確認paused、核對前後SHA／可學權重；主流程另與已完成凍結評估的checkpoint SHA核對。沒有重存模型或重設optimizer。已有工具原本限定sac_mlp128，本次明確增加無LSTM的sac_paper64支援，不放行其他模型。

這些prefix是選定的replay樣本，不是已確認的凍結失敗軌跡。Gaussian輸出是動作變換前參數，不是舵角；Q是模型估計，沒有真實回報校準或TD target，不能直接宣稱Q高估／根因。下一步是否改配方，需配合凍結軌跡與本結果判讀。

進度印出Episode1600／1700、Shared-input probe與Action-value probe。結果在`artifacts/packages/sac-child-probe-20261116`，包含`review.json`、`state_*.json`、`shared_inputs/`、`action_values/`與RESULTS.md。一般錯誤也會嘗試打包現有資料。完成後的Verified ZIP與同名.sha256放回本機根目錄即可；只收本次診斷，不包其他run／完整checkpoint。

只補打包：原命令再加`-PackageOnly`。重跑診斷會重新計算唯讀輸出，沒有訓練或分支建立的副作用；部分失敗以review.status=failed呈現。

驗證：本機R2024b在隔離副本上使用使用者前次交件的真實Agent1600／1700，狀態稽核、共同prefix、16×33×2雙Q推論及來源／權重不變檢查通過（`test_sac_paper_probe`）。未train/sim/pool；PS5.1的Probe+PackageOnly封包SHA核驗通過。完整遠端wrapper仍待使用者執行，局部樣本不證明根因或改善。
