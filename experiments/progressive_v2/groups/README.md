# 實驗組別

日常從這裡進入，不必直接瀏覽混有多次恢復分支的 runs/。

| 組別 | 用途 |
| --- | --- |
| [group_02_recovery](group_02_recovery/README.md) | 前一次已完成的恢復分支；39300 回合成果 |
| [group_03_fresh](group_03_fresh/README.md) | 第三組，新 agent 從頭驗證 |

每組 group.json 記錄已確認的 run-id。原始 run 全部留在 ../runs；這一層是查找入口，不是第二份訓練資料，也不改變 lineage。

Windows 檔案總管使用：在專案根目錄執行下列工具，會在每組的 runs/ 產生指向本機原始 run 的資料夾捷徑。預覽後才 Apply；缺少的本機 run 會標示 Missing，不建立假 run 或下載資料。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/link_experiment_groups.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/link_experiment_groups.ps1 -Apply
```

捷徑只在本機產生，不進 Git；換電腦後重新產生。後續新組別新增 group.json，再執行工具。舊 run 未確認的組別與前段 lineage 不根據檔名猜測；不把截圖中全部資料夾自動歸入第二組。
