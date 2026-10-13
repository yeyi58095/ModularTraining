# JSON 訓練課程：同一 agent，逐階段換軌跡

一份 JSON 描述「要訓練什麼、何時進下一階段、沒學會時怎麼辦」。規劃器解析固定欄位，不執行設定檔內的程式碼；目前採 JSON，尚未支援 YAML。

依 2026-10-09 使用者確認，模型在整份課程最外層指定。階段切換沿用同一個 agent 的 checkpoint 和累計訓練歷史，不重新初始化網路，也不允許每階段偷偷換不同架構。各階段目前可改軌跡、風場與過關／預算條件；學習率與 PPO 超參數仍由 model profile 決定，不在課程中動態調整。

## 直接使用

```matlab
% 只讀與檢查設定，不訓練、不建 pool：
plan = curriculum_plan("curricula/fixed_to_random.json");

% 先建立可檢查的實驗快照，不啟動訓練：
info = retry(curriculum="curricula/fixed_to_random.json", start=false);

% 使用者準備好時才執行：
% info = retry(resume=info.sessionDir, workers=6, minWorkers=1);
```

`curricula/fixed_to_random.json` 不需要外部 MAT，依序使用現有固定路徑函式與現有隨機路徑生成器。條件數字是示範，不是已重現花偉傑論文成效的參數；內建固定路徑亦不能當成論文第一階段路徑的精確復原。

`curricula/two_mat_then_random.example.json` 對應「軌跡1 → 軌跡2 → random」。其中 MAT 尚未提供，可先用 `curriculum_plan(...,checkFiles=false)` 檢查格式；真正建立實驗時必須有有效 MAT。

## 一個階段怎麼寫

```json
{
  "id": "trajectory_one",
  "trajectory": {
    "type": "mat",
    "file": "../trajectories/軌跡1.mat",
    "waypoints_variable": "waypoints",
    "velocity_variable": "velocity"
  },
  "wind": {"east_mps": [0, 0], "north_mps": [0, 0], "turbulence": [0, 0]},
  "advance_when": {
    "all": [
      {"metric": "stage_episodes", "at_least": 5000},
      {"metric": "reward_mean", "window": 100, "consecutive_windows": 3, "at_least": 2500}
    ]
  },
  "max_episodes": 20000,
  "on_limit": "pause"
}
```

含義：此階段至少完成 5000 回合，而且最近三個各 100 回合、不重疊的區間平均 reward 都 >=2500 才進下一階段。跑到 20000 回合還沒通過，就在存檔後暫停。
`consecutive_windows:3` 是最近 300 回合切成三段全部符合，不是同一份日誌被規劃器讀三次，也不是三個重疊的 rolling average。

最外層固定為 `{"schema_version":1,"model":"ppo_lstm128","stages":[...]}`。
`id` 使用不重複的英文字母開頭名稱，例如 `trajectory_one`；MAT 檔名可以用中文。

## 條件字典

| 欄位／指標 | 意義 |
| --- | --- |
| `all` | 裡面條件全部成立，等同 AND |
| `any` | 裡面任一條件成立，等同 OR；可與 all 巢狀組合 |
| `stage_episodes` | 目前這一階段已保存的回合數，不是全實驗累計數 |
| `reward_mean` | 最近 window 回合的平均 reward |
| `steps_mean` | 最近 window 回合的平均步數 |
| `full_length_rate` | 最近 window 回合中，步數 >= steps_at_least 的比例（0～1） |
| `at_least`／`at_most` | >=／<=；每個指標只能選一種 |
| `window` | reward／steps／比例指標必填，資料不足時不通過 |
| `consecutive_windows` | 需連續符合的完整不重疊區間數，預設 1 |

若單純要排程「此階段跑 10000 回合就換」，使用 `{"metric":"stage_episodes","at_least":10000}`。
若要「至少 5000 回合且表現達標」，用 all。不要把最少回合與 reward 寫成 any，否則只要跑滿回合就會過關。
`full_length_rate` 是步數指標，不能當成真正任務成功率；目前環境未提供可供此規劃器判定的獨立成功旗標。

## 軌跡與風場

- `fixed_builtin`：使用 runtime 現有 `createFixedPath()`，整階段維持該路徑。
- `mat`：位置與速度都需為有限實數 N×3 陣列、N>=2 且形狀相同。位置沿用現有模型的 East/North/高度公尺慣例，速度為相應三軸 m/s；不自動猜測座標系、插值或轉換 waypoint-only 檔案。請確認取樣間距、速度及起點適合目前 0.1 秒／15 m/s 環境。
- `random`：必填 `refresh_every_worker_episodes`；10 代表每個 worker 的本地回合計數每 10 回合更新。程序重啟會重置本地計數，不代表全域精確每 10 回合同步換路徑。
- `east_mps`／`north_mps` 是每回合均勻抽取的整數範圍；`[0,0]` 為零風。`turbulence` 是 0～2 的整數範圍。不是任意連續風速或 turbulence 物理量。

MAT 路徑相對於 JSON 所在資料夾解析，不接受絕對路徑。MAT 輸入仍受專案 `*.mat` 忽略規則保護，不會自動上傳 GitHub；雙機準備新實驗時需另行提供這些輸入，或明確決定哪些小型輸入資產要版控。

## 規劃器的執行與恢復

1. `retry(curriculum=...)` 檢查所有階段與 MAT，保存 `curriculum.json` 和 `curriculum_assets/`。後續編輯原 JSON／MAT 不影響已建立實驗。
2. 每個 attempt 選有效 checkpoint，再用其中保存的 EpisodeReward／EpisodeSteps 計算條件。stdout 與 worker-local 計數不作為切換依據。
3. 一段最多執行 `episodesPerProcess` 回合（預設 1000），且不超過當前階段剩餘預算。只在存檔邊界判斷；條件成立後下一段換環境並沿用 agent。不是達到某個 reward 的瞬間中斷平行 workers。
4. `curriculum_state.json` 保存階段索引、階段起始 episode 和已完成階段；重啟後不重複計算上一階段。checkpoint 若早於目前階段起點，或已有 checkpoint 卻遺失狀態檔，拒絕猜測與靜默回滾。
5. 過關判斷優先於預算上限。同時滿足時算通過；未通過而達上限，`on_limit:"pause"` 保存後暫停；明確指定 `"advance"` 才按預算直接進下一階段。
6. 最後一階段 advance 代表課程結束，保存 `Agent_Success.mat`。若原因是 `episode_budget_reached`，只代表預算排程完成，不代表學會任務。`curriculum_outcome.json` 保存實際原因。

課程模式不使用全實驗 `targetReward` 作停止條件，顯式傳入它會被拒絕；過關全部寫在 advance_when。原本沒有 curriculum 的 retry 呼叫仍維持原流程。
平均 reward 圖與 MATLAB 原有歷史仍是全實驗累計；規劃器指標只看當前階段。匯出報告的 learning_health 也改為只看當前階段，避免固定路徑→random 的難度變化直接觸發跨階段退步訊號。

已開始實驗的課程是快照。預算耗盡後直接 resume 同一份設定，仍會停在相同限制，不會自動清零預算；目前不提供執行中改課程或 fork checkpoint 並更換課程的入口。調整原計畫並建立新實驗會從新 agent 開始，勿誤當接續舊權重。
`+trainingcurriculum` 與 runtime 一樣屬執行程式，活動訓練期間不要修改或同步覆蓋它們。

## 驗證範圍

`tests/test_curriculum.m` 在 R2024b 用合成已保存訓練歷史測試條件、MAT 變數映射與快照、跨階段恢復、預算暫停和完成重入；不執行 train()，也不建立真實 worker pool。
尚未完成真實 Simulink 平行訓練的跨階段驗證；使用者尚未提供軌跡1／軌跡2的實際 MAT，因此範例檔仍是待填入輸入的模板。
