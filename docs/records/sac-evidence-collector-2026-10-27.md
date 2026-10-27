# SAC evidence collector — 2026-10-27

使用者希望一次取得幾乎全部 SAC attempt 檔案，以補齊 SAC+LSTM／純 SAC 圖片與 meeting 的實驗時序。已新增 Windows PowerShell 5.1 獨立工具 `tools/collect_sac_evidence.ps1`，操作見[收集指南](../guides/sac-evidence-collection.md)。

依 model.json 選擇 SAC，掃描各課程／模型 runs 及舊 sessions。完整保留已存在的各 attempt 小型檔案、run設定／程式快照／狀態／guard／lineage、評估JSON／CSV／圖，以及相關共用配方、收據與已解包SAC證據。`-IncludeEvaluationTraces` 另納入既有評估MAT軌跡；checkpoint／replay、舊壓縮包及超限檔預設排除，manifest明列。另有明確opt-in，不冒稱預設收集全部模型或可續訓備份。

來源保持原位；沒有讀寫訓練鎖、改control／runtime／課程、連線遠端或啟停訓練。可以讀活動日誌，讀取限制在每檔複製起始長度；來源大小／時間變化會記錄。整包永遠屬逐檔、非原子快照，狀態顯示paused也不能作整體一致性保證。跨機parent_session保留原字串，以run ID查找收集到的父run，缺失／重名列issue，不直接套用舊絕對路徑。

每次使用唯一ZIP名，逐檔計算封包內容SHA256並讀回ZIP核驗；全部通過才將`.partial`發布為ZIP。附manifest及ZIP SHA sidecar，不上傳。失敗保留半成品，沒有刪除或解鎖來源的修復行為。

驗證：

- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_collect_sac_evidence.ps1` 通過：SAC／PPO辨識、兩分支全部attempt、舊機parent路徑對應、活動state標記、無效JSON issue、trace與checkpoint opt-in、大小／鎖／快取／舊封包排除、ZIP逐檔SHA、來源不變及重跑不覆寫。
- 額外合成32MiB growing log，在同程序C#背景writer持續append時執行收集：成功結束、bytes_exported小於後續來源長度、changed_during_copy=true，未啟動MATLAB或正式訓練。
- 專案實際`-Preview -IncludeEvaluationTraces`成功，當次發現本機21個SAC metadata run／11個attempt，包含過去本機測試fixture；不是遠端正式run數量或訓練狀態證明。預覽沒有建立封包或修改來源。
- 未在遠端實跑；Windows PowerShell 5.1本機fixture封包測試不等於遠端全量數十GB模型打包已驗證。未補造缺少的1001–2000日誌、歷史loss或未執行的評估。

下一步：使用者在有完整SAC資料的遠端副本執行收集指南，回傳`Verified ZIP`所列檔案；核對manifest／SHA、各run範圍後再補齊圖表。封包不加入Git，工具／文件／測試可同步。
