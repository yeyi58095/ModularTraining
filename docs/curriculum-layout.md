# 以課程管理實驗，保留既有訓練

2026-10-10 起，新建 curriculum 實驗依課程 JSON 的檔名分組：

```text
curricula/progressive_v1.json           課程定義，指定模型和各階段條件
configs/lab_gpu6.json                  硬體與重試設定
+trainingmodels/ppo_lstm128/            模型定義
experiments/progressive_v1/runs/
  <時間_唯一碼>/
    curriculum.json                   此實驗的課程快照
    curriculum_assets/                軌跡輸入快照
    curriculum_state.json             實際階段分界與進度
    model.json、model_source/          此實驗使用的模型及原始碼
    control.json                      此實驗的硬體／執行設定
    Agent_Final.mat、checkpoints/      可用 checkpoint（訓練後產生）
    attempt_*/、diagnostics/、runs/    日誌與分段紀錄
```

課程名稱取自 JSON 檔名；不同目錄中同名 JSON 會被分到同一組，但每個實驗有獨立 ID 與快照，不會互相覆寫。課程改版建議另取 progressive_v2 等名稱。模型是課程參數；更換模型會建立不同實驗，並不代表不同架構可直接沿用權重。

非 curriculum 訓練仍使用 `+trainingmodels/<model>/runs/`。已有課程實驗無論放在此舊目錄或新目錄，都依 `retry(resume=完整實驗路徑)` 原位續用，不會被自動搬到新位置。新舊資料夾都受 Git 忽略。畫圖及報告工具可搜尋兩種結構。

## 正在實驗室跑的那次怎麼辦

1. 保留目前 `+trainingmodels/ppo_lstm128/runs/20261009_201547_...` 原位，讓既有 supervisor 繼續執行。不需要為分類改變而停止訓練。
2. 不搬移、不改名、不刪除該實驗，也不編輯其 control／curriculum 快照。活動中的程序持有舊絕對路徑，移動資料可能造成後續讀寫失敗。
3. 現在若只要 stage 分界圖，只複製新版 `plot_training_rewards.py` 到實驗室，停止並重新啟動畫圖工具。不要在訓練中整包更新會被後續 attempt 載入的執行程式。畫圖工具只讀訓練資料、寫圖與 CSV；停止它不會停止訓練。
4. 等訓練正常結束／暫停、supervisor 與 worker 都退出後，將整個實驗資料夾備份到另一位置；不要只備份單一 MAT。課程狀態、輸入與模型快照也需要保留。
5. 再更新完整程式。可指定原路徑續訓，或使用下方工具把已停止的實驗複製到新結構；不支援活動實驗搬移或跨課程匯入。

GitHub 的精簡 report.json 不是模型備份；MAT 與完整實驗仍留在原電腦。這次變更沒有操作實驗室檔案，不能取代對遠端磁碟／備份的確認。

## 把已停止的實驗接續到新結構

2026-10-10 使用者已回報實驗室 attempt 8 為 stopped，並要求在新結構繼續這次模型。先在實驗室專案根目錄更新程式，再執行 PowerShell：

```powershell
git pull --ff-only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\migrate_training_session.ps1 -SourceSession "D:\daniel\ModularTraining\+trainingmodels\ppo_lstm128\runs\20261009_201547_tpf1292058_f8ca_4ccd_bc7f_a66b20ee91b4" -CurriculumName progressive_v1
```

工具取得 supervisor 排他鎖、拒絕活動狀態／已存在目的地／外置 diagnostics／連結目錄。完整複製到暫存位置，逐檔 SHA256 比對並保留原檔；只修正新副本的 control.json 執行路徑與 status／STOP，完成後才發布到 `experiments/progressive_v1/runs/<原實驗 ID>/`。模型、課程狀態、輸入與歷史日誌保持原始內容；歷史日誌裡的舊路徑不改寫。複製全部資料需額外磁碟空間，雜湊驗證也可能花時間。

失敗會保留原件與可能存在的 `.incoming_*` 暫存資料，絕不自動刪除；不要拿暫存目錄續訓。成功後仍不自動訓練。原 `matlabExe` 保留，同機續訓時 retry 會再以目前 MATLAB 更新它；此工具不是任意跨機遷移工具。

MATLAB 的 Current Folder 切到實驗室專案根目錄：

```matlab
clear retry verify_training_session
newSession = fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261009_201547_tpf1292058_f8ca_4ccd_bc7f_a66b20ee91b4");
verified = verify_training_session(newSession);
% 上行成功並確認顯示的 episode/stage 合理後，才執行：
info = retry(resume=newSession);
```

驗證函式讀取最新可用 PPO checkpoint、真實累計回合數與課程位置，不啟動 pool 或訓練。不可讀的最新檔案會列出並嘗試較舊候選；若候選皆無效或早於目前階段起點，拒絕通過，不能從零開始冒充續訓。停止前未存檔回合仍需重跑。原件保留但不要同時續跑兩份。

畫圖工具請停止舊 watch 並重新指向 `newSession` 的新完整路徑；MATLAB 的 info 在續訓後也會指向新位置。GPU、workers、階段及既有模型設定由副本保留，無須重跑 prepare_progressive_training 或新實驗入口。

## 圖上的階段分界

灰色虛線仍代表 attempt 邊界；橘色點劃線代表實際 stage 切換。Episode 軸下方標示 Stage 1／Stage 2 與階段 id。如果 Stage 2 的 start_episode=3000，線畫在 3000 與 3001 之間。

標記只讀該實驗的 `curriculum.json` 和 `curriculum_state.json`，不依 JSON 預算或 reward 猜分界。沒有課程紀錄的舊實驗仍可畫 reward；狀態讀取不完整或不一致時會警告並暫不畫 stage，下次 watch 更新再讀取。

2026-10-10 修正：MATLAB 重新編碼單筆 completed 時可能從陣列變成物件，畫圖端現在兼容兩種形狀；原先會誤報 Incomplete stage history。這不需要修改實驗 JSON 或停止訓練。PNG 改為暫存檔完成後原子替換；寫入失敗保留前張成功圖片，watch 提示後重試，持續失敗可關閉圖片檢視器或改用 --output 路徑。PNG 與 CSV 仍是分別輸出，不是兩檔交易式快照。

啟動指令不變，務必指定正在跑的實驗完整路徑，避免自動選到別的測試實驗：

```powershell
python plot_training_rewards.py "D:\daniel\ModularTraining\+trainingmodels\ppo_lstm128\runs\20261009_201547_tpf1292058_f8ca_4ccd_bc7f_a66b20ee91b4" --watch 30
```

驗證：MATLAB 以 start=false 確認新目錄、舊課程目錄原位續用、非課程模型目錄相容；Python 驗證新舊搜尋、3000.5 分界、無課程／無效狀態，以及既有報告／退步診斷。另用合成資料產圖檢查標籤，非實驗室真實曲線。不重跑真實訓練。
