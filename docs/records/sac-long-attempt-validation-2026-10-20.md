# SAC、長 attempt 與待辦收尾

授權：使用者要求挑選候選演算法、實作並可在本機試跑，延長單attempt至500–1000回合，完成可執行待辦並提供遠端下一步。未連線遠端、未啟動遠端訓練。開始修改runtime前本機無MATLAB程序；遠端由使用者回報第三組17200正常保存paused。

## 實作

- `sac_lstm128`：MATLAB R2024b recurrent SAC、雙Q critic、自動熵、uniform sequence replay。新agent獨立八階段 `sac_spatial_v2`，沿用spatial_v2與原門檻。PPO不能轉成SAC續訓。
- 原配方 `lab_gpu6_progressive_v2.json` 的新run預設每程序1000、checkpoint100；既有run的control／模型／課程快照未改。恢復工具允許500／1000等整數guard窗口，17200配方不改LR、額外2000回合上限；guard規則屬工程保護，不是驗證最優。
- callback只在checkpoint頻率邊界或段落上限請求正常返回；engine先保存Agent_Final才正式判定課程／guard。遇到達標／退步可提前結束長attempt。重啟seed頻率隨之改變，不能把所有分數差歸因於演算法。
- Custom options必須一次建構。先將回呼寫入AverageReward options在R2024b報型別錯誤，原待辦字面順序撤回；新實作通過實際飛行。
- Windows PowerShell5.1解析UTF8無BOM中文註解時出錯，相關PS1加入UTF8 BOM，邏輯不變。
- 遠端整理封裝入口先驗paused與排他鎖，再呼叫既有organize／compact／groups工具，不搬run。本機預覽Nothing to organize/compact，遠端未操作。
- `review_round3`封裝4次有／無探索配對評估；`shadow_learning_review`重播保存歷史，只提出建議，不改任何run狀態或啟動／介入。完整自動控制器未交付。

## 驗證證據

- `test_sac_candidate`：CPU合成環境兩回合64步，再保存／載入後訓練兩回合；actor實際更新、模型驗證、replay長度保留與增長。公開保存選項包含optimizer／targets，不宣稱私有optimizer逐位等價。
- `test_sac_flight`：兩回合實際spatial_v2、CPU／1worker、兩個程序與測試用階段，229／84步。配置500回合上限，階段條件在1回合時觸發，證明可提前返回保存。跨階段actor與replay保留；其後5步凍結評估通過雙critic權重不變檢查。
- 本機測試run：experiments/curriculum/runs/20261020_152135_tp1afe61ab_21df_4685_86c9_d68155949d8e。只驗接線、保存及接續；測試用簡化階段門檻不代表學習成功。
- `test_curriculum`、`test_training_progress_display`、`test_modular_training`、`test_recovery_guard`、`test_continuous_training`、`test_tool_layout`通過。log：tests/output/sac-regression.log。
- `test_long_attempt_boundaries`通過100回合條件／退步判斷、monitor不暫停、階段隔離與程序上限；`test_long_recovery`通過500／1000分支準備、100回合guard與父control不變。`test_continuous_flight_model`結構回歸通過。log：tests/output/long-attempt-final.log。
- PowerShell：episode_format、compact_workspace、organize_reports、experiment_groups、finish_workspace_layout、diagnostic_package通過。驗證原檔保留、雜湊、重跑、活動／鎖衝突拒絕。
- Python：learning_health四項、tool_paths一項通過。全面Python discovery未通過：第一次tools匯入路徑與sandbox TEMP不可用，修正路徑後仍缺matplotlib；未宣稱全部Python圖表測試通過。本次未改Python實作。
- git diff --check通過；MAT、ZIP、完整log、使用者PPTX與ppo_lstm_fromgenimi.md不納入提交。

## 連續模擬與Stage8

獨立連續模型、已保存Stage8 seed902情境、39300成果、無探索，3000步CPU模擬完成，原done紀錄存在且非零樣本數0。因此只證明完整輸入與模擬入口可運作，尚未驗證超標後恢復；不作標準過關證據。來源checkpoint SHA `9b4aeb016dafcca917ce2a479baee65f8a7a8342bab9ab19c9e893c56e559cd1`，SLX SHA `3b8081d6a53a56ff1335cb15d5350576302e3b50e5dba2348810cd6b66a3dc04`；前後未改。

另唯讀分析原「有探索」Stage8 seed902 trace：10秒後guidance距離峰值47.587506m、279.9秒，該時obs3還原roll約17.3977度。峰值前後5秒記錄的原始action範圍約-5.5152至4.0343。這是RL trace原始值，不能直接稱為實際舵面飽和；尚需核對動作到控制器的限幅／尺度鏈。原trace SHA `d9fc6b174f37c9c0a2c9fed5b56ff9a16b1e513698d80a3f9be1fd7504799b28`。不能憑這些同時發生的量判定偏離物理根因。

shadow測試以來源封存的獨立測試副本重播39300回合、393個邊界，動作執行數0、階段狀態與checkpoint不變，不使用未來回合。

## 尚需遠端／後續研究

遠端完整編排同步、groups捷徑、第三組16000／17200凍結診斷及可能的SAC長期實驗仍由使用者執行。未驗證GPU／6workers性能、SAC從頭收斂、跨情境泛化、原PPO失敗根因、完整自動調LR／選分支。下一步見[操作指令](../guides/round3-next-steps-2026-10-20.md)。
