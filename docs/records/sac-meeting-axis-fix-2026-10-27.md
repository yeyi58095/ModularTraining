# SAC meeting座標軸空白標題修正 — 2026-10-27

使用者回報第9頁Replay配對評估圖出現多個重疊座標軸標題。已在本機原生PowerPoint以唯讀開啟原檔，匯出第9頁重現相同問題。先前Artifact Tool的render未顯示這些預設文字，因此先前目視檢查未抓到，不能將其視為PowerPoint外觀已驗證。

原因：匯出檔20個圖表共有25個沒有實際文字／cache／公式的軸 `c:title`，內容只有字型樣式 `c:txPr`。PowerPoint將這些節點當成標題占位符，顯示預設「座標軸標題」，與刻度及類別名稱重疊。原私有builder的chart font helper對沒有實際標題的軸也寫titleTextStyle，觸發此狀況；helper已限縮為只對有內容的軸標題寫字型。

修正檔：`output/meeting_sac_20261027/dist/SAC_Meeting_20261027_AxisFixed.pptx`，245,839 bytes，SHA256 `6d9c077662aec4ccd7770d66229f431111d72218cd6971a6555be1ac22bc6994`。

原檔 `SAC_Meeting_20261027.pptx` 保留，SHA仍為 `d0ebb09ae611acd54f777460b772b269717986ca50ce0e9c3286d64e49df440d`。只移除空白軸title節點，保留Episode及Pre-squash mean等實際標題；數值、刻度、圖表主標題不改。全部非chart-XML部件逐位元一致，包括20個內嵌XLSX、所有投影片、表格、notes與relationships。各chart XML核對僅有指定移除的語義變更。

新增可重用工具 `tools/repair_pptx_axis_titles.py`，只用Python stdlib，拒絕覆寫來源或既有目的檔，輸出修正清單與hash；來源輸出ZIP皆讀回驗證。`tests/test_repair_pptx_axis_titles.py`確認移除空白、保留有文字／cache／公式的軸標題及圖表主標題，並確認重複清理不再變動。

驗證：

- 原生PowerPoint唯讀開啟修正候選，匯出全部24頁，檢查13個含圖表頁各張原尺寸圖片，並掃描全24頁總覽；第9頁與其他圖的預設標題已消失，實際Episode／mean標題保留。
- PowerPoint只關閉本次唯讀開啟的presentation；不保存原檔，不終止使用者原有presentation。未手動開啟Chart Edit Data視窗，不擴張這項驗證結論。
- 最終檔與PowerPoint已核對候選SHA完全相同。套件、字型、版面、native圖表與workbook、first-party import均通過，layout finding=0。驗證檔位於 `output/meeting_sac_20261027/build/axis-fix/validation.json`。
- Before/after PowerPoint原生PNG及總覽在 `build/axis-fix/`，清理報告在 `repair-report.json`。私有build與簡報不加入Git。
- 另嘗試同步live artifact，但重匯入交易超過session8MiB上限，未保存；本次以已驗證的本機修正PPTX作交付，不宣稱live session已同步完成。

未修改訓練runtime、run、來源紀錄、模板或使用者原有其他簡報，未啟停訓練。未變更實驗結果或簡報結論。
