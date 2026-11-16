# Actor LR短對照：同一1600、兩組各100回合

本輪是診斷後的假說試驗，不是已證明的修復。從child `20261114_211021_recovery_tp4c32126b` 的Agent1600（SHA45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c）分別建立baseline與actor_half，保留來源paused，不續跑2100。

## 遠端執行

這份專案沒有活動訓練時，在PowerShell執行；此命令會依序啟動兩組有界訓練，不再等確認：

```powershell
Set-Location 'D:\daniel\ModularTraining'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\review_sac_child_history.ps1 -ActorPilot
```

1. 來源paused／已保存2100／budget停止、model／LR／GPU六workers及Agent1600 SHA核對，執行GPU／profile能力檢查，不冒稱實際建池已驗證。
2. 源Agent1600先測無風／弱風：原診斷seeds2000011501–2000011510，加上新固定seeds2000011601–2000011610，共40次CPU無探索飛行。新路線不作挑選候選，保留完整結果。
3. baseline新子run：actor LR=1.5e-4；最多新增100至1700，GPU／同步六workers，checkpoint100、maxAttempts1，原guard保留。訓練正常結束後同40次評估。
4. actor_half另由同一1600建立：只改actor LR至7.5e-5，critic3e-4、entropy設定、replay50000、原課程均保留；同樣最多100回合後同40次評估。先前baseline不接續、不把它的模型拿來初始化候選。
5. 正常結束兩者都paused，**整套最多新增200回合，不自動選勝者續訓**。本輪Stage2起點已有600回合，每臂再100仍不足原1000回合升階最低條件；不放寬條件來升階。

兩組指定相同training_seed=20261116，但平行採樣／策略改變使軌跡、噪音消耗時序、總步數與更新數不一定一致。equal episodes不稱equal steps公平預算。review.json會記錄每臂實際新增回合、步數、訓練平均reward與停止原因。兩組各一次是初步比較，需後續判讀，不是可靠的因果或泛化統計。

總共120次凍結飛行（各最多3000步）加兩組最多100回合訓練，仍可能耗時數小時。保持終端開啟，不讓電腦睡眠；不要在執行中pull改runtime。

## 保護與交件

每次準備／啟動先寫入意圖紀錄；已經準備或啟動過而中斷時，重跑會拒絕重複建run／訓練。完整完成後重跑只打包。一般錯誤會嘗試收集已停止子run資料並封包，不能把partial或failed當作完成。退步guard、異常退出、非正常budget停止均停止後續自動工作，不重試錯誤，也不解除原run暫停鎖。

結果目錄`artifacts/packages/sac-actor-pilot-20261116`，包含protocol、reference1600、兩臂訓練設定／lineage／日誌／Agent_Final、兩臂凍結評估與comparison.json。RESULTS.md表格分原診斷與新路線兩組。只收本輪資料，ZIP逐檔SHA核驗後印Verified ZIP；將ZIP與同名.sha256回傳本機根目錄。

只補打包可加`-PackageOnly`。希望完成目前有界工作後不啟動後續臂／評估時，在另一視窗建立：

```powershell
New-Item -ItemType File -Force .\artifacts\packages\sac-actor-pilot-20261116\CANCEL
```

取消不強制終止當前訓練／評估；在該批工作完成後檢查。不要刪review.json或鎖繞過重複啟動保護。

## 驗證邊界

`test_sac_actor_pilot`使用隔離假評估／假程序驗證兩臂各100、三份成對報告、完成不重開、中斷意圖拒絕。`test_sac_actor_pilot_preparation`使用使用者交回的真實Agent1600隔離副本，檢查兩配方的網路權重、replay及trackerIDs、Adam moments、critic/entropy optimizer與PolicyState，只有候選actor LR改變。這些是準備／推論與流程測試，不是本機正式訓練、遠端六worker長跑或改善證明。
