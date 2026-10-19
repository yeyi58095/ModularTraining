# 課程進度顯示（2026-10-18）

Reward 圖會保留橘色 stage 分界，在 N 與 N+1 之間畫線，標明 N 是上一階段最後回合、N+1 是下一階段第一回合。來源是 run 保存的課程歷史，沿用 lineage 裁切；不根據 reward、課程預算或圖形位置推測切換。

圖下新增進度面板，列出該 run 快照中的目前條件：stage episodes、reward mean、steps mean、full-length rate 的指定步數與比例門檻、每區間回合數、連續達標區間數，以及 PASS/WAIT。ANY 只需其中一組通過，ALL 需全部通過。最後階段目標顯示 complete course；已保存成功 outcome 顯示 COURSE COMPLETED。

`training_status(sessionDir)` 同樣列出切換、目前條件、未達原因、資料截至回合與正式 outcome。MATLAB 狀態工具沿原 parent 路徑或同層唯一同名目錄讀取祖先；Python 圖表另支援 `--lineage-root`。搬移後找不到祖先時，不補造數據。

```matlab
training_status(info.sessionDir);
```

```powershell
python tools/plot_training_rewards.py "<run 路徑>" --watch 60 --view
```

Python 畫圖現在需要一起帶上根目錄 `tools/curriculum_progress.py`。更新 MATLAB 顯示要一起帶上 `+trainingcurriculum/progress.m`、`progress_callback.m`、`log_history.m`、`decide.m`、`training_status.m` 及引擎修改，且應等副本沒有活動訓練。此次只修改本機，沒有直接更新遠端或 commit/push。

## 暫算與正式判定

- 即時 callback 使用 MATLAB 提供的歷史原值，行末標示 provisional；正式切換仍在保存 checkpoint 後執行。callback 只在原本段落上限回傳 stop，原生 MaxEpisodes 仍是同一上限；不因顯示條件達標提前停訓。
- `training_status` 和 Python 圖表讀取 stdout，reward 已四捨五入，屬 log estimate。靠近門檻時，不能拿暫算取代 checkpoint 原值的正式判定。
- 每條指標獨立計算最新、不重疊的完整區間，與現有課程判定一致。不把不同指標的 streak 改成共用計數器。
- 只讀完整換行列。同一 run 重複回合由較新 attempt 覆蓋；祖先只讀到 fork checkpoint，子 run 只讀接續後回合。缺失位置填未知值，不把不連續記錄壓成連續區間。
- stage episode 數依最後可見 episode 與保存 start_episode 的差；指標遇未知資料不顯示通過。若完全無可見資料，不能推斷最新進度。
- 正式 outcome 顯示自身的截至回合及 decision/reason。舊日誌缺失不會推翻已有的正式成功紀錄。
- 非課程日誌格式保持原流程。課程新增資訊接在 Q0 後；原有 reward 圖與精簡報告的欄位保持可解析。歷史日誌不補寫。

## 驗證範圍

MATLAB `test_curriculum`、`test_training_progress_display` 使用合成歷史、假引擎，覆蓋保存／接續／完成、ALL/ANY、at_most、缺區間、非有限值、分支缺口與 callback 的原有回合上限。Python 測試覆蓋 stage/lineage、進度計算、正式完成顯示、PNG 寫入和既有 parser；另實際生成八階段合成圖檢查標籤與面板。

未啟動正式訓練，未做遠端 GPU／多 worker live callback 驗證，未修改既有 run 快照、reward、agent 或 guard。工作區在接手前已有 continuous-training／guard 相關修改；它們不是本次顯示改善新增的功能。
