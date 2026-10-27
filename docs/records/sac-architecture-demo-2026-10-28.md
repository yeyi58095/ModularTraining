# SAC 架構展示與PPT連結 — 2026-10-28

依使用者澄清，10/27 meeting主網頁應負責互動架構，不是報告文章。已唯讀檢視10/14 LabStyle包：最後一頁以相對hyperlink開啟流程／架構HTML；training-explorer以全畫布與可調大小原文側欄為主。10/14使用者PPT未修改。

本次沿用該操作方式，更新既有output/meeting_sac_20261027：

- docs/index.html：SAC系統架構，8個方塊對應retry、快照、supervisor、引擎、checkpoint、guard、課程、凍結評估。
- docs/lstm-explorer.html：SAC＋LSTM，7個元件與對應原文，UseRNN=true、128 units、SequenceLength32。
- docs/mlp-explorer.html：純SAC（MLP），7個元件與對應原文，UseRNN=false、128 hidden units、SequenceLength1。
- docs/report.html：前次SAC說明、比較及結果，放到另一分頁。原diagrams/training-explorer.html入口導向系統圖。
- 同一份dist/SAC_Meeting_20261027.pptx新增第25頁，四個相對連結：../docs/index.html、../docs/lstm-explorer.html、../docs/mlp-explorer.html、../docs/report.html。圖中文字採繁中；固定圖形檢視器UI為英文。

新頁使用Artifact Tool從原第20頁版型建立，再僅追加新slide／notes及包註冊；舊24頁、20圖表、內嵌XLSX、masters、layouts與舊notes等193個原部件逐位元不變。保留原版與候選於build/pptx-before-linked-delivery-20261028-verified.zip，核驗後移除重複PPTX；日常只維護原dist檔名。

最終PPT SHA256：c5e97004d084c470cc8ffffb27c2102d9b3f8fa5936e5e8d4f4b90a49ffd51aa，249241 bytes，25頁。Finalizer package／font／layout／native chart／first-party import通過，layout findings=0。原生PowerPoint唯讀匯出第25頁並確認四種相對hyperlink目的（文字與shape各一個）；目視核對版型及文字。沒有宣稱已在使用者USB電腦實際點擊；外部檔案開啟提示依PowerPoint本機設定。

三張Archify原圖各9項artifact checks通過、0 errors／warnings；四種桌面viewport的visual-check通過。三個explorer的22個可點擊方塊、原文、課程JSON、搜尋、明暗及補充分頁以離線Chrome驗證，無JS錯誤；明暗及新PPT頁截圖已目視檢查。工具收據／截圖均於build及docs/*.visual-check.*，不納入USB。

中途自動審核因帳戶usage limit無法執行額外Chrome檢查，並非安全否決；使用者要求繼續後重新嘗試已成功。另修正新PPT的OOXML hyperlink順序，並處理finalizer收據不可覆寫等本機建置問題。僅將成功驗證的最終版本發布。

USB固定更新output/SAC_Meeting_20261027_USB.zip。完整解壓、保持dist與docs相對位置即可從PPT第25頁或START_HERE.html開啟；核心圖、原文和圖表離線可用。歷史文件中的外部專案路徑未完整打包。兩架構是獨立初始化，不表示PPO可轉SAC，也未新增訓練、評估、修改runtime或既有run。
