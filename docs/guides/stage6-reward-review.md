# 41600 暫停後的配對評估

本批次使用既有空間循跡環境，驗證 SLX SHA256，並比較同一 run 中的
Agent31600、Agent33700、Agent41600。缺檔即停止，不以其他 checkpoint 代替。
評估不訓練、不解除 guard、不修改 checkpoint 或正式 SLX。

在實驗室訓練已暫停後，先於 PowerShell 的專案根目錄執行
`git pull --ff-only` 更新工具，不需要手動傳送或解壓工具 ZIP。
確認模型視窗已關閉，再於 MATLAB 的專案根目錄執行：

```matlab
clear compare_training_checkpoints audit_training_rewards review_stage6_checkpoints
rehash
session=fullfile(pwd,"experiments","progressive_v1","runs", ...
    "20261014_000404_recovery_tp3b623159");
batch=review_stage6_checkpoints(session);
disp(batch.summaryZip)
```

共 45 次 CPU 純模擬：Stage 6 seeds 201:210 的 30 次配對、seeds 202/205
的 6 次 reward 分解、前三階段 seed 101 的 9 次保留能力檢查。
每次上限 3000 步，時間依電腦而異；不是 45 回合訓練。
重複的詳細案例用來拆解 reward，不當成新的獨立樣本。

批次輸出位於 run/reports/stage6_review_<時間>_<唯一碼>/。
完成後顯示的 ZIP 只有五個 JSON，適合先分享；完整 MAT traces 留在各
evaluation 資料夾。ZIP 不是可續訓備份。發生錯誤時，已完成評估與 batch.json
仍保留，先提供錯誤及 manifest，不必重跑已完成的模擬。

以同 seed 的 reward、步數與逐項 reward 差異判讀，不用不同環境的訓練曲線
證明學習改善。observation7 是正規化訊號，不直接稱為公尺；詳細診斷保留
guidance 與原始路徑，可另核對物理距離。這批固定種子的結果不等於正式合格。

本次更新只涉及評估工具、測試與說明，不修改 runtime、課程設定、模型或
訓練資料。先前提供的工具 ZIP 已不需要；評估完成後產生的結果 ZIP 才是
要分享的資料。若實驗室有未提交修改導致 Git 拒絕更新，先保留並比對差異，
不要用 reset --hard 覆蓋。
