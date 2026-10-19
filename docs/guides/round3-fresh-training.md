# 第三組：新 agent 從頭驗證

順序為目錄重構驗證 → 使用者 push → 實驗室 pull 與本機整理 → 開訓前核對 → 另行啟動。這份文件與 preflight 不代表已啟動；不接續 39300、18500 或其他 checkpoint。

第三組是新的實驗組別，沿用 progressive_v2 八階段及 spatial_v2，不改名為 progressive_v3（沒有建立新版課程）。模型為目前 ppo_lstm128 定義，依初始化建立新 agent，各階段沿用同一 agent。這不是沿用成功模型或其人工干預／恢復設定，也不是已驗證能從頭收斂的結論。原課程預算與暫停條件維持；自動 LR／分支選擇尚未實作。

確認該副本沒有活動訓練，於專案根目錄 PowerShell：

```powershell
git status --short
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw '保留本機變更，先處理 pull 錯誤。' }
powershell -NoProfile -ExecutionPolicy Bypass -File tools/compact_workspace.ps1
# 確認清單後再加 -Apply
```

於 MATLAB 專案根目錄先只做輸入準備與核對：

```matlab
rehash
trainingtools.prepare_progressive_v2_training();
third = trainingtools.preflight_round3();
```

輸入準備只建立缺少的軌跡資產，既有內容不同則拒絕覆寫；preflight 不寫檔、不建 run、不建 agent、不開 pool。檢查八階段、spatial_v2 模型 SHA、start=false 與無 resume，回傳當前課程 SHA、模型及設定。共享課程若日後修改，需重新審視輸出，不把此檢查當作全部歷史設定的完整等價證明。

下一步經確認才以 start=false 建立新的獨立 run：

```matlab
args = namedargs2cell(third.config);
thirdRun = retry(args{:});  % config 中 start=false，僅建立新 run
disp(thirdRun.sessionDir)
```

先核對新 run 的 environment.json、curriculum.json、model.json 與 control.json，記錄第三組 run-id，再另行啟動。不得用既有成功模型目錄當 resume 來源。當前尚未建立正式第三組 run，亦未承諾從頭收斂、多 worker 穩定或跨情境穩健。
