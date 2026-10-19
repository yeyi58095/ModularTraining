# 完成模型：20261017_071436_recovery_tp323769ed

| 項目 | 實際結果 |
| --- | --- |
| 課程／環境 | progressive_v2／spatial_v2（spatial_reward_v2） |
| 完成 | 累計 39300 回合、attempt 224、conditions_met |
| 恢復來源 | 20261017_005709_recovery_tp1d90ab61 的 Agent18500.mat |
| 無探索評估 | Stage1–8，seeds901:910，80/80 跑滿 3000 步 |
| 探索評估 | Stage4–8，seeds901:910，50/50 跑滿 3000 步 |
| 保留限制 | Stage8 seed902 後段偏離 47.59m；固定路徑多 seed 不等於多條路線 |
| 完整訓練歷程 | 本機成果封存未包含所有祖先／attempt 日誌及 checkpoints，尚未完整登錄 |

這是包含恢復分支的已完成實驗，不是新 agent 從頭收斂的證明。3000 步不等於完成整條路線。模型與受評估 Agent39300 的可學權重及公開選項相同，optimizer 私有狀態未驗證。

本機模型為此目錄的 `Agent_Success.mat`；SHA256 與來源見 [provenance.json](provenance.json)。MAT 不隨 git pull 下載。

## 取得模型與評估

在專案根目錄執行（需要既有 gh 登入與 Draft Release 存取權）：

```powershell
python training_artifacts.py sync --tag "result-20261017_071436_recovery_tp323769ed-e177d217bc1f"
# 若也需要無探索的完整評估：
python training_artifacts.py sync --tag "result-20261017_071436_recovery_tp323769ed-49e0834c5ef8"
```

下載至 `artifacts/results/<tag>/`，工具核驗 SHA256；模型是其中的 `Agent_Success.mat`。sync 目前不會自動複製到 completed_models。此處本機副本已存在，另一台可直接從核驗後封存載入模型。封存內同時提供課程與環境快照、恢復 metadata 和評估 traces；不是完整可直接 retry 的 run。

[完整評估與限制](../../../../docs/records/success-evaluation-2026-10-19.md) · [同步操作](../../../../docs/guides/github-artifact-sync.md)
