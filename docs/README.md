# 文件入口

平常從這三個入口開始即可：

- [文件首頁](index.html)：可搜尋全部文件，依操作、研究與紀錄分類。
- [流程與程式原文](diagrams/training-explorer.html)：方塊流程、原文、課程 JSON 範例。
- [程式關係架構圖](architecture.html)：各元件之間的關係；[閱讀說明](reference/architecture-notes.md)。

## 資料夾

```text
docs/
├─ README.md                 文件索引
├─ index.html                文件首頁
├─ architecture.html         既有架構圖入口
├─ guides/                   操作與設定
├─ research/                 問題調查與候選方案
├─ records/                  日期工作／驗證紀錄
├─ reference/                架構說明、簡報來源與搬移對照
└─ diagrams/
   ├─ README.md              互動圖使用與更新
   ├─ training-explorer.html  流程與原文入口（位置保留）
   ├─ src/                   JSON、HTML 模板、建置／檢查工具
   ├─ assets/                純流程圖 HTML
   └─ evidence/              收據、來源 SHA、截圖與驗證紀錄
```

## 操作與設定

| 要做的事 | 文件 |
|---|---|
| 查看六階段計畫 | [training-plan-v1.md](guides/training-plan-v1.md) |
| 設定課程 JSON | [curriculum.md](guides/curriculum.md) |
| 實驗室啟動 | [lab-start.md](guides/lab-start.md) |
| 看目前正式 endpoint V2 環境與續訓操作 | [endpoint-v2-training.md](guides/endpoint-v2-training.md) |
| 理解課程／run／報告分類 | [curriculum-layout.md](guides/curriculum-layout.md) |
| 看保存後暫停及恢復分支 | [recovery-training.md](guides/recovery-training.md) |
| 比較 checkpoint | [checkpoint-comparison.md](guides/checkpoint-comparison.md) |
| 做 Stage 5 配對評估 | [stage5-evaluation.md](guides/stage5-evaluation.md) |
| 稽核續訓來源 | [resume-audit.md](guides/resume-audit.md) |
| 跨機分享診斷 ZIP | [diagnostic-package.md](guides/diagnostic-package.md) |
| 看退步診斷的規則與限制 | [learning-health.md](guides/learning-health.md) |
| 看初始化修正及環境版本判讀 | [startup-path-fix.md](guides/startup-path-fix.md) |
| 跨 run 畫 reward 繼承曲線 | [run-lineage-proposal.md](guides/run-lineage-proposal.md) |

## 研究與工作紀錄

- Stage 3 調查：[低分回報](research/lab-regression-2026-10-10.md)、[trace 發現](research/lab-trace-findings-2026-10-10.md)。
- Stage 5 調查：[trace 發現](research/stage5-trace-findings-2026-10-11.md)、[endpoint 候選開發歷史](research/endpoint-lookahead-candidate.md)。
- 2026-10-09：[專案審視](records/review-2026-10-09.md)、[短測紀錄](records/validation-2026-10-09.md)。
- 2026-10-12：[程式註解與互動圖更新](records/code-comments-2026-10-12.md)。
- 參考：[架構說明](reference/architecture-notes.md)、[簡報來源](reference/presentation_sources.md)。

## 舊檔名與驗證素材

原文件的檔名保持不變，只移到上述分類。文件首頁可以用舊檔名搜尋；完整前後位置見 [搬移對照](reference/documentation-layout.json)。本次只修改 `docs/`，根目錄 `README.md`、`AGENTS.md` 及其他文件中的舊路徑沒有改寫，遇到舊連結可從本索引找到新位置。

驗證 JSON 收據內的絕對路徑是當時產物位置，保留作歷史證據；截圖與其 contact sheet 成組搬移。沒有刪除歷史文件，也沒有更改訓練、run 或 checkpoint。
