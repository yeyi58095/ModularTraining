# 一次執行：半速 SAC 評估、選擇、有界續訓與交件

使用者 11/14 授權由遠端腳本自動評估不同 episode、依明確規則選分支並續訓，符合條件可升階。本輪只處理 `20261107_132924_recovery_tp578fea3e` 半速來源，不掃描舊 SAC/PPO 來挑模型。來源已在 2000 因 recovery_budget 暫停。遠端仍由使用者啟動。

## 執行

先確認這份專案沒有活動訓練，再在遠端 PowerShell 執行：

```powershell
Set-Location 'D:\daniel\ModularTraining'
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw '同步失敗，請貼回錯誤；不要強制覆寫。' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_sac_review_cycle.ps1
```

這個指令已包含訓練授權的執行步驟，達標後不會再等確認。保持終端開啟，電腦不要睡眠。使用 PATH 中的 MATLAB；需 R2024b、可用 GPU 及至少六 workers 的 Processes profile。能力檢查不開 pool，實際建池由訓練驗證，失敗不自動重試。

## 固定規則與工作量

1. 核對收據、model=sac_paper64、paused／2000／recovery_budget、actor LR=1.5e-4、critic LR=3e-4、GPU、六 workers、checkpoint100；預先載入核對六份 checkpoint 的 episode 與 SHA。
2. Agent1500、1600、1700、1800、1900、2000，各測無風與弱風各十條，CPU、無探索、每次最多3000步，共120次。選擇 seeds 為2000011401–2000011410，超出原訓練seed範圍且與課程gate分開；是固定測試集，不代表無限泛化。
3. 每個階段至少8/10跑滿且沒有environment_done；弱風中至少五條實際有風，其跑滿率至少80%；各階段不得比同批Agent1500少超過一次跑滿。依「較弱階段跑滿數、兩階段總跑滿數、較弱階段平均步數」排序，同分選較早episode。reward不作排序，以免不同風況reward混用。
4. 只對選出的候選與1500基準，用2000011501–2000011510另測無風／弱風，最多40次；同樣門檻，失敗就停止，不拿複核集反覆挑第二名。沒有候選或複核失敗仍產生結果ZIP。80%是本輪試跑篩選門檻，不是正式課程90%門檻，也不是論文訓練成功率。
5. 通過後另建一個子run，初始checkpoint位元組複製與SHA一致；保留課程、環境、LR、replay及原guard。GPU／同步6workers，每100保存，**從選中episode起總共最多新增500回合**，非固定跑到2500。來源run不解鎖、不續訓、不改快照。
6. 每次supervisor只准一個attempt。只有原課程條件成立／要求frozen evaluation時，才評估同一Agent_Final的原課程gate（指定seeds、後10秒距離max≤20m、RMS≤10m等以快照為準），通過且guard未paused、總預算未用完才啟動下一attempt。由既有curriculum.prepare移動stage，同一agent接續；不改state或門檻。整個cycle最多四次supervisor啟動，錯誤、退步guard、課程預算或500回合預算都停止。若條件在預算用完才滿足，本輪不另加預算升階。
7. 訓練後再用複核路線評估最終模型的無風／弱風／當前stage（去重，最多30次）。這是固定測試集上的前後比較，不是獨立訓練seed統計。完整順利流程最多約220次飛行加500回合訓練，可能耗時很多小時；無法用先前單段耗時精準預測。

## 進度、取消與重跑

結果資料夾固定為 `artifacts/packages/sac-review-cycle-20261114`。`cycle.json`記錄目前phase、child、saved_episode、launches；訓練時終端每分鐘顯示等待訊息，真正回合進度可在另一視窗查看child的stdout。流程刻意不自動打開圖表視窗。

希望正常做完目前工作後停止後續流程時，在另一個PowerShell執行：

```powershell
New-Item -ItemType File -Force .\artifacts\packages\sac-review-cycle-20261114\CANCEL
```

評估會在目前checkpoint批次結束後檢查；訓練會完成當前有上限attempt後停止後續升階／評估。不用Ctrl+C當正常暫停方式，也不建立run的STOP來強殺當前attempt。

已完成的評估會在核對輸入與檔案SHA後略過。任何準備／啟動意圖一旦寫入，中斷後重跑不會重新建分支或重複啟動，需交回資料判讀。完成、無候選、複核失敗或取消後，重跑只打包。勿刪cycle.json、CANCEL或鎖來讓它再跑一輪。

僅補打包（例如終端被關閉後，先確認流程已停止）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_sac_review_cycle.ps1 -PackageOnly
```

若子run仍被鎖住，只封存cycle並在manifest註記未收子run，不能當作完整訓練結果；待停止後再PackageOnly。正常流程等待supervisor退出後才打包。

## 交件

結尾印出 `Verified ZIP:` 和SHA256，ZIP位於 `artifacts/packages/sac-review-cycle-<時間>-<識別碼>.zip`。複製ZIP及同名.sha256回本機專案根目錄即可。

ZIP只收本次cycle和它新建的子run：

- `cycle/RESULTS.md`：可直接閱讀的(1)候選比較與(2)續訓結果入口。
- `selection.json`、`holdout.json`、每份evaluation.json／軌跡、complete.json來源SHA。
- `cycle.json`、`selected_recipe.json`、`training_summary.json`、`gate_*.json`、最終凍結評估。
- 子run設定、lineage、attempt日誌、worker記錄、checkpoint與Agent_Final（單檔256MiB上限，排除項會標示）。

壓縮後逐檔讀回核對SHA才發布正式ZIP；不含其他歷史run。不是完整可續訓備份，也不會自動上傳或Git提交模型。

## 本機驗證邊界

隔離假評估／假引擎測試包含：正常選擇與複核、跨stage仍共用500上限、無候選、複核失敗、gate失敗、重複執行、資料損毀與中斷啟動拒絕。另用真實封存Agent1500與合成停止狀態測試位元組保留的子run準備、錯SHA拒絕；沒有本機正式訓練。PowerShell5.1驗證打包內容／逐檔SHA與活動子run排除。這些不等同已實測遠端六worker長訓、實際升階或收斂。
