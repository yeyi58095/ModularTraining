# 跨機診斷 ZIP（不進 Git 歷史）

在已停止的實驗室副本，用 PowerShell 執行：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pack_training_diagnostics.ps1 -SessionPath ".\experiments\progressive_v1\runs\20261010_155437_recovery_tpebed29a8" -EvaluationName "evaluation_20261010_183235_tp0d559eeb"
```

預設選取 Agent10600／10700、runs/r000001 的初始 agent／訓練選項／腳本快照、課程及恢復設定、指定完整 evaluation 的 JSON 與 traces、稽核 JSON 及 attempt 診斷日誌。可用 -Episodes 10600,10700,11000（直接以 PowerShell 呼叫腳本時）調整 checkpoint；預設兩個足以調查第一次退步。不納入模型快取或全部歷史 checkpoint。這是診斷子集，不能用作完整續訓備份。

ZIP 寫入專案 diagnostic_packages/（Git 忽略），含 manifest.json 的逐檔大小和 SHA256；封裝後重新讀 ZIP 核對每個來源雜湊。工具持有 supervisor 排他鎖並要求停止狀態；不更動來源，不上傳。失敗留下 .partial 供調查，不會冒充成功 ZIP。實際大型檔案的時間／大小須以實驗室結果為準；本機通過合成小檔案測試。

## GitHub 傳送

在 repository 的 Releases → Draft a new release，填獨立標籤如 diagnostics-20261010-recovery，將 Verified ZIP 對應的檔案加入附件，選 Save draft。不要用 Add file 將 ZIP 提交到程式碼，也不要以 git add -f 加入 MAT。

草稿下載需要可存取草稿的帳號；宿舍端用相同／有權限帳號下載，告知本機 ZIP 路徑與打包印出的 SHA256，即可驗證後分析。如果改成正式發佈，先確認 repository 可見性與附件內容（檔案可能包含機器路徑）。啟用 immutable releases 時，正式發佈後有附件修改／刪除限制，診斷用途保持草稿即可。

這裡的工具不自動建立 Release、刪除附件或重寫 Git 歷史。附件傳完後可手動刪除草稿；已下載的副本不會隨之刪除。

參考：[GitHub 管理 Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
