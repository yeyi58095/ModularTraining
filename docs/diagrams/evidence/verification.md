# 驗證紀錄（2026-10-12）

- diagram_type: workflow
- validation: 9/9 showcase，0 errors，0 warnings
- specification_sha256: cda8dfe715b138bb5440349ce1c3a79810b16139e0b105cbdf1dc3d5641bd825
- artifact_sha256（Archify 主圖）: 7eafcc1aaa73455a9498ba8aa41c086739f78e5f2789055abd9022f11e5b20b4
- artifact_sha256（程式碼探索器）: 85aa14c858a74dfeb935701e52b4666232e42497d4412e1b9c0b31552e407f6e
- browser_evidence: passed（主圖 visual-check）
- visual_review: passed
- correction_rounds: 2（主圖配置；探索器另外修正側欄與連結整合）

主圖由 Archify 產生並保持原樣，探索器內嵌該主圖與 19 個來源檔快照（含課程 JSON）。主圖瀏覽器證據見 `training-flow.visual-check.json`；探索器的另外驗證見 `training-explorer.check.json`，不混用兩者的 artifact SHA。

探索器在 1440×900、1600×1000、1920×1080、2048×1320 沒有外層頁面溢出；已以真實瀏覽器測試 12 個步驟與 1 個課程範例入口、每個對應區段原文一致、19 份內嵌來源與工作區一致、完整檔案切換、實際 SVG 點選、搜尋、指定步驟連結。課程範例完整 JSON 與六階段分頁逐一 parse 並核對。側欄程式碼區允許捲動，以閱讀長檔案；主圖使用原 viewer 縮放功能。

實際查看了主圖及探索器的淺色／深色截圖、展開程式碼畫面、課程 JSON 範例與 2048×1320 概覽；確認文字、箭頭和原文側欄可讀。側欄開啟時覆蓋右側圖區，關閉即返回完整圖；這是閱讀操作的設計。

圖表驗證未啟動 MATLAB、Simulink、pool 或正式訓練。本次另對來源補上註解，並以 MATLAB Code Analyzer 靜態檢查；沒有執行 train／sim／pool。原始碼註解更新與行號重映射見 [工作紀錄](../../records/code-comments-2026-10-12.md)，可執行內容保持不變，未修改 run、checkpoint、SLX 或控制設定，也未 commit / push。

後續互動驗證使用真實 mouse pointer：100% 拖曳後 `exit` 方塊完整移到側欄左側，重設回原位置；側欄左／下／角落拖曳及方向鍵尺寸控制有效；程式碼拖曳產生水平捲動，換行時內容寬度落在閱讀區內。新增互動只在探索器包裝層，已驗證主圖 HTML 與 SVG 規格保持原樣。圖表匯出操作前清除探索器的額外平移，避免帶入輸出。

## docs 分類整理後

流程入口 `docs/diagrams/training-explorer.html` 保持原位置。規格與模板移到 `../src/`，純圖放在 `../assets/`，此處集中收據與截圖；重新建置後完成同一套互動驗證。歷史圖表收據內的原絕對路徑保留，不偽造搬移後的新驗證紀錄。

新增文件首頁 `docs/index.html` 與 root README；22 份文件可搜尋與在首頁閱讀，39 個 Markdown 本機連結均存在，54 個搬移檔案均保留。首頁在 1440、1600、1920、2048 與 800 寬度無水平溢出；已查看淺／深色截圖。結果見 `docs-layout.check.json`，搬移對照見 `../../reference/documentation-layout.json`。此次檔案編輯／搬移範圍只限 docs。
