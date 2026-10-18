# progressive_v2：18000 受限恢復試驗

本頁保留 2026-10-16 的歷史配方與診斷背景；2026-10-19 經使用者授權納入 Git 同步，不是目前已完成39300後的下一輪訓練指令。連續模式另見 [continuous-training.md](continuous-training.md)。下文的未提交與待執行描述為當時狀態。

本配方 configs/recovery_v2_18000_guarded.json 從停止的原始 spatial_v2 run 的 Agent18000.mat 另開分支，沿用環境快照、課程與同一agent。不是修復根因的保證，也不是最佳模型認證。

Actor LR由5e-5減至2.5e-5，critic不變。這是控制更新幅度的待驗證干預，不把前次退步直接歸因於LR。每100回合保存／換程序；新增最多1000至19000。相同階段兩個連續100回合視窗的reward及steps都低於參考80%時，在保存邊界pause；不是每步監控，仍可能先退步。保留原課程過關條件。

來源歷史截至18000的guard預檢未觸發：參考16300，reward2679.4、steps3000；最後100回合reward2528.7、steps2908。現階段約2143.5 reward與2400 steps兩者都低於才算低窗，參考可能隨後續改善更新。到新stage重新依該階段歷史建立參考。

本機僅有18400/18500/18600 checkpoint。預檢用18400保存歷史截到18000，不冒充持有Agent18000；驗證兩窗觸發、一窗容忍、在記憶體改18400 actor LR不變更權重、spatial_v2模型SHA一致。未做18000完整prepare、正式訓練或GPU測試。實驗室prepare會檢查實際18000、父狀態／鎖、LR、環境快照並生成新分支。

使用者可在實驗室MATLAB建立相同配方後prepare_recovery_training，再retry(resume=新run)。不要刪原run的STOP或guard、不要從18600直接續訓。新run停止後應用固定配對情境評估來源與新checkpoint，再決定延長。資料與配方本次本機保存，未自動提交或推送。
