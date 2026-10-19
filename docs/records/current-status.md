# 目前狀態與接續入口

更新：2026-10-19。這是專案狀態摘要，不是遠端即時監控或所有聊天室的逐字備份。

## 已完成

- 使用者貼回實驗室輸出，確認已 fast-forward 至 7ded2ea。compact_workspace 僅預覽根目錄 2 個 Python 快取檔，尚未 Apply；未收到第三組 MATLAB preflight 結果。使用者已授權後續已授權修改由代理自行 commit/push，詳見 AGENTS。

- 根目錄縮編完成：19 個工具移至 tools/ 與 +trainingtools/，呼叫與根目錄定位已更新；簡報建置資料／根快取 118 檔已搬移核驗、12 份腳本保留原稿後調整路徑。43 項 Python、5 組 PowerShell、6 組 MATLAB 檢查通過；其中一組包含合成 CPU PPO 兩回合，無正式飛行訓練。詳細證據、資料保護與限制見 [重構紀錄](layout-refactor-2026-10-19.md)。本次由使用者後續 push；遠端未更新本次重構。
- 第三組開訓前入口 trainingtools.preflight_round3 已通過本機核對，固定八階段 progressive_v2／spatial_v2，從新 agent 開始；沒有建立正式第三組 run。依 [第三組準備](../guides/round3-fresh-training.md) 先同步與核對，再建立新 run、另行啟動。

- 2026-10-19 後續整理：根 README、文件入口、課程首頁與完成模型卡串接；workspace-layout 補完整目錄分工、遠端 main 的 pull 指令及驗證後複製模型步驟。整理工具預覽回報 Nothing to organize，沒有搬動 run。PowerShell 核對上述 Markdown 本機連結、模型 SHA256、Git 白名單與 MAT／日誌／未知 JSON 排除均通過；git diff --check 通過。Python 系統別名不可執行，故用 PowerShell 完成檢查，未執行 MATLAB 或訓練。簡報與 ZIP 的使用者變更排除於本次提交。

- 課程成果展示入口已加入 [experiments](../../experiments/README.md) 與 [progressive_v2](../../experiments/progressive_v2/README.md)。Git 白名單只放行課程／成果 README 和逐模型 provenance.json，MAT 與完整日誌仍忽略。39300 成果卡保留恢復來源、評估限制及下載指令；未宣稱從頭收斂。未實作自動登錄或完整訓練歷程封裝，未新增曲線。這次僅調整文件與忽略規則，未啟動訓練。

- 依使用者希望從課程內查看完成模型，本機已新增 `experiments/progressive_v2/completed_models/20261017_071436_recovery_tp323769ed/Agent_Success.mat`；從探索評估 Release `e177d217bc1f` 封存複製並核對來源／目的 SHA256 相同，旁附 `provenance.json`，入口有 README。此處僅供完成模型查找與評估，不是完整可續訓 run；原封存與既有 run 未移動。未啟動 MATLAB／訓練，未推定另一台已同步。

- progressive_v2 run `20261017_071436_recovery_tp323769ed`：39300回合、attempt224、conditions_met，使用者確認沒有啟動新run。
- 無探索Stage1–8共80次、探索Stage4–8共50次都跑滿3000步。不是130個獨立情境；[完整驗收與限制](success-evaluation-2026-10-19.md)。
- Agent_Success與Agent39300的actor／critic可學權重及公開AgentOptions一致；optimizer私有狀態未驗證。
- 兩份成果Release已下載到本機並通過SHA256：tag尾碼 `49e0834c5ef8`（無探索）、`e177d217bc1f`（探索）。來源與路徑見驗收紀錄。
- 階段邊界與條件進度顯示已實作；[操作說明](../guides/training-progress-display.md)。連續模式可明確啟用，但不是自動LR控制器；[限制](../guides/continuous-training.md)。

## 下一步

1. 依[整理工具](../guides/workspace-layout.md)統一兩端目錄用途；遠端由使用者執行。
2. 實驗室已 pull 目錄重構至 7ded2ea；可完成快取整理，再於 MATLAB 執行第三組輸入準備與 preflight。尚未收到其核對結果，未建立正式新 run 或啟動。舊根目錄工具指令須換為 tools/ 或 trainingtools 套件。
3. [JSON自動決策](../research/autonomous-curriculum-proposal-2026-10-18.md)仍是提案：先可重播的shadow判斷，再獨立validation、有限延長與恢復。未實作自動LR／選分支。
4. Stage8 seed902後段47.59m偏離保留為回歸案例；根因尚未分析，不能藉放寬50m門檻宣稱修復。

## 查找紀錄

- [歷史交接原文](project-history-through-2026-10-19.md)：原AGENTS完整封存，內含當時狀態與已失效的待辦描述；勿當作目前狀態。
- [文件索引](../README.md)、[離線可搜尋首頁](../index.html)、[配方分類](../../configs/README.md)。
- 各聊天室沒有自動完整寫入專案；重要新決策需更新本頁，細節另寫records／research並在AGENTS保留必要規則。歷史文獻與結論不改寫成最新結果。
