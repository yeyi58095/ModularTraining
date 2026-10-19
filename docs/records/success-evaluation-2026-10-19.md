# 完成模型與探索評估核驗

來源 run：20261017_071436_recovery_tp323769ed，checkpoint 39300。無探索評估 evaluation_20261018_234801_tpc304c6c6（Stage1–8、seeds901:910）80/80跑滿；探索評估 evaluation_20261019_075841_tpdf0ef65f（Stage4–8、相同seeds）50/50跑滿3000步。兩份 Release 已同步本機並經 SHA256 驗證，後者 tag 為 result-20261017_071436_recovery_tp323769ed-e177d217bc1f。

本機唯讀 MATLAB 比較 Agent_Success.mat 與 Agent39300.mat，actor／critic 可學參數及公開 AgentOptions isequaln 相同；兩個 MAT 雜湊不同，但讀取前後各自 SHA 不變。未核對 optimizer 私有狀態，未執行 train/sim。

探索組使用 useExploration=true、explorationStdScale=1；模型本身已有0.5倍率，沒有再縮放。Stage4–8平均reward依序2669.4176、2632.5904、2631.2990、2504.8058、2502.2036。

Stage8 seed902：東風參數3、北風參數1m/s、turbulence=2；reward2353.1222，3000步。觀測還原 guidance 距離最大47.587506m，出現在279.9秒；3001個觀測中37個>=40m、21個>=45m，不能把樣本數直接當成連續事件長度。獨立有限原路線距離在10秒後最大亦為47.587506m、RMS11.919254m、P95為24.421037m。全程原路線最大50m在初始t=0，與上述後段偏離分開解讀。已確認真實後段偏離，未分析其控制／路段更新因果。

這批測試通過，但不是130個獨立情境或泛化可靠度保證；階段之間可能抽到相同風參數，固定路徑多seed也不等於多條路線。保留本例作回歸診斷，不將其當成未看過的最終測試集。

下一輪方案仍採新agent、固定spatial_v2、八階段順序。核對成功run快照：階段最低回合依序2000/3000/3000/5000/2000/3000/5000/10000；所有表現指標均連續三個100回合區間，末階段reward>=2200、steps均值>=2900、3000步比例>=95%。這是既有門檻基準，不代表新agent已驗證能從頭通過。

先保留此課程與環境基準，不因本例調reward或放寬50m門檻。後續自動決策應分清平台期、探索脆弱與確定性退步，透過獨立validation再決定有限延長／恢復；關閉guard並不能替代這套控制器。詳細提案見 ../research/autonomous-curriculum-proposal-2026-10-18.md。未建立新正式run或啟動訓練。
