# 課程與實際訓練成果

每個課程的 `curriculum.json` 是目前配方，`completed_models/` 是完成模型的成果入口，`runs/` 保留原始實驗。

| 課程 | 已登錄成果 |
| --- | --- |
| [progressive_v2](progressive_v2/README.md) | 39300 回合完成模型、無探索與探索評估 |

成果代表該次 run 的實際經驗；以封存的課程、環境與恢復 lineage 為準，不保證目前配方重新訓練必然得到同樣結果。

往後每個完成模型使用 `completed_models/<run-id>/` 登錄 README 與 provenance.json；不同 run 各自保留，不覆寫舊成果。README 記錄課程／環境、完成回合、恢復來源、評估與限制、Release tag、訓練歷程是否完整。模型 MAT 保留本機並透過 Release 同步，Git 只同步上述小型索引。這是登錄慣例，目前沒有訓練完成後自動登錄的 hook。

訓練過程也值得保存：Git 適合放經確認的精簡摘要與少量曲線；完整日誌、逐回合資料與 checkpoints 另存帶 SHA256 manifest 的附件。現有 `tools/training_artifacts.py` 封裝模型與評估，尚未封裝完整訓練歷程；沒有拿到的歷程應明確標為缺少，不補畫或宣稱完整備份。曲線尚未加入 Git 白名單，須在產出並核對後指定檔案。

操作見 [成果同步說明](../docs/guides/github-artifact-sync.md)。
