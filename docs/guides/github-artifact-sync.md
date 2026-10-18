# GitHub 雙機成果同步

程式碼、課程 JSON、精簡報告維持 Git push/pull；模型與完整評估使用同一個 repository 的 **Draft Release 附件**。`git pull` 不會下載附件，`training_artifacts.py sync` 才會下載並驗證它們。兩端的活動 run 不互相覆蓋。

## 一次性準備

兩端需 Python 3.9 以上（只用標準函式庫）與 GitHub CLI `gh`。若日常畫圖用的是 `py` 或特定 Python 路徑，下列 `python` 換成同一個執行檔。

Windows 可從 [GitHub CLI](https://cli.github.com/) 安裝，或在 PowerShell 執行：

```powershell
winget install --id GitHub.cli --exact
```

安裝後重開 PowerShell，再登入：

```powershell
gh auth login --hostname github.com --web
gh auth status --hostname github.com
python --version
```

兩台以有 repository 寫入權限的帳號登入，才能存取 draft。工具使用 `gh` 既有認證，不讀出、不保存 token。repository 自動取自腳本所在專案的 `origin`，只接受 github.com HTTPS／SSH URL，不硬編碼本機或實驗室路徑。

## 實驗室：一個指令封裝並上傳

先確認來源 run 沒有活動訓練／評估。在 PowerShell 更新程式後執行：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
python training_artifacts.py publish --session "experiments/progressive_v2/runs/20261017_071436_recovery_tp323769ed" --evaluation "evaluation_20261018_234801_tpc304c6c6"
```

完成會印出 `Uploaded and download-verified DRAFT`、tag，以及另一台可直接貼上的完整 `sync` 指令。把這段輸出貼回聊天即可。這次 run 的資料來自使用者回報：39300 回合完成，seeds901:910、八階段共80次無探索評估全跑滿；模型與完整 traces 尚未由代理在本機驗證。

若只想先產生與檢查本機包，將 `publish` 換成 `pack`；pack 不需要 gh 或網路。封裝成功後再用相同 publish 指令會重用內容相同的包。

## 宿舍：一個指令下載並核對

在宿舍專案更新程式、登入 gh 後，使用發布端印出的實際 tag：

```powershell
python training_artifacts.py sync --tag "<發布端印出的完整 tag>"
```

結果在腳本所在專案的 `artifacts/results/<tag>/`。兩端專案根目錄不同沒關係；不會把檔案寫進 `experiments/` 或父 run，不會改寫 JSON 裡保存的原機器路徑。那些路徑是歷史 metadata，不代表下載後可直接使用。

**這是模型與評估封存包，不是完整可續訓 run。** 不包含 supervisor.lock、所有 attempts、全部歷史 checkpoints；不得對下載目錄直接 `retry(resume=...)`。後續本機分析直接讀封存資料；若要以既有 evaluator 重播，須另行建立經驗證的評估工作副本，而不是偽造停止狀態或擅自修寫原快照。

## 包含與驗證內容

- `Agent_Success.mat`，以及 evaluation.json 實際列出的受評估 checkpoint。相同 episode 不等於兩個 MAT 容器雜湊相同，因此各自保留與標示；工具不宣稱成功模型權重已與評估模型比對。
- model.json、model_source/、environment.json、environment/；所有環境檔案核對快照 SHA，MAT 課程輸入核對存在且一併打包。
- curriculum.json、curriculum_state.json、curriculum_outcome.json、control.json、status.json，以及存在時的 recovery／guard JSON。
- 指定完整評估的 evaluation.json、scenarios.mat、results 列出的逐次 MAT traces。評估必須屬於此 run、包含完成回合、環境和課程 SHA 與目前快照吻合；受評估 checkpoint 必須仍有相同 SHA。
- manifest.json：每個檔案的路徑、大小和 SHA256，以及 run、回合、evaluation、封裝工具當下的 Git commit／dirty 狀態。封裝工具版本**不等於歷史訓練執行版本證據**。
- ZIP 外另有同名 JSON，保存 ZIP 大小、SHA256 及 manifest 身分。tag 由 run 名稱與 manifest hash 前12碼生成；資料不同建立另一版本，不覆蓋舊版本。

來源包在 `artifacts/packages/`，下載包在 `artifacts/downloads/`，三個目錄均受 Git 忽略。可保留本機包以便離線搬移：先搬同名 ZIP／JSON，再執行 `python training_artifacts.py import <JSON路徑>`，仍有完整雜湊檢查。

## 停止、重跑與失敗語意

封裝要求 status=success、outcome.success=true，且取得與 MATLAB supervisor 相容的 Windows FileShare.None 排他鎖。鎖失敗、檔案缺失、環境漂移或未完成評估會停止，不修改來源。Linux 使用 flock，跨平台的鎖不能用來推論 Windows 遠端正在停止。

上傳建立 draft，不直接公開發佈、不修改既有 Release 狀態；不使用 `--clobber`。上傳中斷後再次執行相同 publish，先核對 release 的內容身分，只補缺少的附件。若已有同名但內容不符的附件，下載驗證會失敗，保留遠端與本機原件，需人工檢查。

發布成功前會重新下載 ZIP／JSON，檢查整包與逐檔雜湊。sync 在驗證所有 ZIP entries 後才解壓，拒絕路徑穿越、Windows 保留名稱、大小寫重複、連結及額外未列明檔案；使用暫存目錄完成後再發布。已下載版本再次 sync 會重新核對，若本機內容被改動則拒絕覆寫。失敗的 `.partial`／下載暫存資料保留供調查，不當作完整成果。

Draft 附件可能包含原機器路徑及完整研究資料；本工具不自動把 draft 改為公開 Release。每個附件須小於 GitHub 的2 GiB限制，目前超限會明確拒絕，尚未實作分卷。同步會用到 ZIP 加解壓資料的磁碟空間；不是持續鏡像或排程。

## 驗證與限制

`tests/test_training_artifacts.py` 以合成檔案測試成功封裝／匯入、重跑、來源不變、活動狀態與排他鎖拒絕、環境及checkpoint漂移、缺輸入、未完成評估、ZIP／逐檔雜湊、路徑攻擊、大小寫衝突、超限、認證失敗及模擬 gh 上傳重試／下載毀損。沒有使用真實模型或建立測試 Release；實驗室首次發布是實際網路端到端驗證。

官方 CLI 介面：[create](https://cli.github.com/manual/gh_release_create)、[upload](https://cli.github.com/manual/gh_release_upload)、[download](https://cli.github.com/manual/gh_release_download)。
