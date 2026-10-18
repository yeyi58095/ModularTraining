# 下一輪課程與 JSON 自動決策評估（提案，未實作）

使用者希望一次啟動後，正常情況能完成整個課程，必要時仍可介入。2026-10-18 回報 progressive_v2 run `20261017_071436_recovery_tp323769ed` 於 39300 回合、attempt 224、`conditions_met` 完成，時間為 19:31:16 +08:00。這是使用者提供的完成證據，不是本機讀取的遠端即時狀態。完成課程尚未取代獨立評估。

## 先驗收這次成果

在實驗室新 MATLAB session，保持訓練停止，先針對最新 checkpoint 做八階段、每階段 10 個固定 seed 的無探索評估，共 80 次 CPU sim。沿用 run 的環境快照與模型內探索倍率，不重新縮放 std。固定路徑的多 seed 不代表十條不同軌跡；既有 turbulence 內部 seeds 亦不等同獨立噪音序列。檢查完成率、失敗情境及原始路線距離，不以訓練 reward 一項驗收。

```matlab
cd D:\daniel\ModularTraining
sessionDir = fullfile(pwd,"experiments","progressive_v2","runs", ...
    "20261017_071436_recovery_tp323769ed");
review = compare_training_checkpoints(sessionDir, ...
    episodes=[],includeLatest=true,stages=1:8,seeds=901:910, ...
    maxSteps=3000,useExploration=false,routeMetrics=true);
disp(jsonencode(review.summary,PrettyPrint=true))
```

這組 seed 是候選評估組，尚未核對完整歷史，不能先稱為從未使用過的保留測試集。下一步依結果安排探索開啟的配對評估；不在同一命令直接啟動新訓練。這 80 次可能耗時，工具逐次保存結果。若要作正式可靠度主張，另訂樣本數、獨立情境生成與信賴區間。

## 下一輪課程排序

建議先做「固定版本、新 agent、從頭可重現」的 progressive_v3，維持八階段的任務遞進，避免同時改 reward、環境與大量難度。這不是沿用已成功 agent 的第九階段。

| 階段 | 任務 | 自動驗證重點 |
| --- | --- | --- |
| 1 | 直線、無風 | 初始循跡與數值正常 |
| 2 | 平緩 S 彎、無風 | 基本轉向，保留直線能力 |
| 3 | 固定轉彎、無風 | 曲率任務，保留前兩階段 |
| 4 | random、無風 | 路徑變化，追蹤探索與無探索差距 |
| 5 | random、小穩定風 | 初步風擾適應 |
| 6 | random、小風與湍流 | 風擾組合 |
| 7 | random、較強風與小湍流 | 提高風強度 |
| 8 | random、完整風場 | 最終任務與全階段能力保留 |

從第一回合固定 spatial_v2 環境，包含現有空間循跡修正；不修改既有 run 快照。新 run 必須凍結環境 SHA、課程、模型、監督策略、root seed 與情境生成版本。現有門檻只作起始候選，須先核對成功 run 的實際快照，再依獨立評估結果決定，不從共享 JSON 推定歷史設定。

## 把任務課程與訓練控制策略分開

`curriculum.json` 定義每階段任務與過關門檻；另以 `controller.json` 定義觀測、條件與允許動作。run 保存兩者的不可變快照。沿用明確的 `all/any`、比較運算、完整區間、連續次數，不接受任意 MATLAB/Python 表達式或 eval。**現有 schema 不支援下列草案，不能直接交給 retry。**

```json
{
  "proposal_schema": "controller-v1-draft-not-executable",
  "decision_boundary": "saved_checkpoint",
  "rules": [{
    "id": "confirmed_regression_actor_lr_half",
    "priority": 20,
    "when": {"all": [
      {"signal": "training.regression", "equals": true, "consecutive_checks": 2},
      {"signal": "validation.paired_regression", "equals": true},
      {"signal": "validation.current_stage_compatible_checkpoint", "equals": true},
      {"signal": "stage.intervention_count", "at_most": 1},
      {"signal": "stage.episodes_since_intervention", "at_least": 1000}
    ]},
    "then": {
      "action": "fork_from_validated_checkpoint",
      "actor_learning_rate_scale": 0.5,
      "critic_learning_rate_scale": 1,
      "trial_additional_episodes": 500,
      "on_validation_failure": "pause"
    }
  }],
  "limits": {"max_total_interventions": 4, "on_exhausted": "pause"}
}
```

所有數值都是待校準的控制預算例子，並非已證實最佳超參數。LR 下限必須按模型設定明訂；不允許無限減半或自動提高 LR。候選checkpoint應有可比且未過期的評估，若屬較早階段，須明確恢復其階段狀態並重驗後續任務，不可挪用目前的已過關狀態。

## 決策順序與限制

1. 檔案／SHA 不一致、非有限權重或指標、使用者 STOP、鎖衝突，立即保存可用資料並暫停；不得用調 LR 遮蔽問題。
2. 可恢復的程序或授權失敗，走現有有限重試／worker 降級，不更改學習參數。
3. 到 checkpoint 邊界且沒有安全故障，評估過關與舊任務能力；全課程通過才結束。
4. 訓練疑似退步先觸發固定 validation 情境的配對評估。訓練低分但無探索仍穩定時，不直接判定 LR 過高；記錄探索 std 分布，只有已驗證並預先授權的介入規則才可動作。
5. 獨立驗證確認退步，且仍有介入預算，才從相容的驗證 checkpoint 開一個子 run、只改一項參數。父 run 與 checkpoint 不改；短試跑通過才能延長。候選失敗則暫停，第一版不做無限搜尋樹。
6. 平台期不等於退步：若能力穩定但門檻未達，可在總回合／時間預算內延長一段；不自動降低門檻或略過階段。確認長期無進展才用另一條經驗證的規則處理。
7. 同一保存邊界只提交一次動作，按固定優先序選擇；冷卻期間禁止再次介入。每次動作寫入原因、數據截至回合、規則版本、來源 SHA、父子 run 及結果。

控制器需要持久狀態與具冪等性的 `evaluate -> prepare -> verify -> activate -> complete` 流程。中斷後先核對已建立子 run，不重複減半、重複建分支或同時啟動兩個 run。STOP 在所有狀態優先；遇到未知狀態暫停。

## 評估資料不能反覆洩漏到最後驗收

使用固定 validation 情境做調參與候選選擇，另留封存的 final test 情境，控制器不可依 final test 選 LR 或分支。定期刷新 validation 的程序與 seed 也需記錄。初版可先每 1000 新回合及階段切換時評估；疑似退步追加評估，避免每 100 回合跑全套而拖慢訓練。頻率仍待量測成本。

探索倍率 0.5 在這次恢復中的成功不能直接證明新 agent 從頭也適合固定減半；下一輪先凍結一個有依據的模型設定，保留獨立實驗比較。變更 actor 建構與 setActor 對 optimizer 私有狀態的影響尚未驗證，不能自稱完全無損續訓。

## 分段實作與驗收

- 第一步：純腳本入口準備新 run，明確 seed 與完整快照，start=false 預覽。先做 shadow controller，只記錄「若啟用會採何動作」。
- 第二步：以歷史重播、合成退步、缺資料、ANY/ALL、冷卻、預算耗盡與中斷重啟測試控制器；核對沒有看未來資料或跨階段拼錯歷史。
- 第三步：啟用定期評估及有限延長；驗證其不改 agent、checkpoint、guard 或課程門檻。
- 第四步：只開放一種有限恢復介入（候選是 actor LR 減半），驗證來源權重、模型快照、學習率實際生效、可恢復狀態與單一活動分支。探索倍率調整另行評估。
- 第五步：使用者審閱完整 JSON 計畫後，一次啟動完整新課程；只在完成、故障、介入耗盡或需要人工決策時通知。

目標是減少例行干預，不承諾任何 seed 都一定收斂，也不以關閉 guard、取消所有預算或無限 retry 達成表面上的「不停」。本次只完成規劃，未建立 controller、未啟動新訓練。
