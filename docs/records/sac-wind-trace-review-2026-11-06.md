# 1300 與 1400 配對軌跡及下一步

使用已核對過 SHA 的 40 份軌跡，原件位於 artifacts/incoming/sac-wind-history-20261106。唯讀 MATLAB 抽取程式及輸出為 artifacts/wind_trace_review_20261106/review.m、trace_summary.json。

每對 stage/seed 取兩模型皆有資料的前 min(steps) 範圍，排除前 100 個取樣。觀測7乘30為 guidance distance，觀測3乘40為規範化滾轉角的度數換算。這次沒有把 guidance distance 當成獨立原路線距離。結果如下：

- 1400 的最大絕對滾轉角比1300高，無風和弱風各9/10條。
- guidance RMS 增大，無風7/10、弱風6/10條。
- 平均絕對相鄰動作差增大，無風5/10、弱風4/10條；二十情境平均從0.3422降到0.3314。
- 動作飽和比例逐情境平均從0.681%升至1.700%，仍不能據此判定飽和是根因。
- seed517 在1400的兩風況皆呈roll_threshold終止觀測。共同區間內最大絕對滾轉由約15.6度增至39.9度；終端觀測另含門檻判定。相同時長內 guidance RMS 反而略低，顯示只看距離摘要會漏掉姿態問題。

下一步用現有 inspect_sac_checkpoint 唯讀稽核六份保存狀態，檢查 entropy、optimizer欄位、critic與target差距、有限數值及近期replay摘要。以上都是診斷證據，尚未確認學習率或entropy為原因。新增 audit_sac_wind_history 入口，核對前次凍結評估checkpoint SHA，收集到原交件資料夾的 checkpoint_audit。

遠端同步後在新 MATLAB R2024b 工作階段執行：

```matlab
cd('D:\daniel\ModularTraining'); addpath(pwd); rehash;
auditFolder = trainingtools.audit_sac_wind_history();
disp(auditFolder);
```

完成後可只打包 checkpoint_audit 資料夾交回。此稽核尚待遠端真實六份 checkpoint 驗證，本機僅完成MATLAB靜態檢查；既有trace讀取未啟動飛行或訓練。
