# 六份 checkpoint 稽核與 actor 半速候選

收到 checkpoint-audit-20261107-002136.zip，完整六份報告的 checkpoint SHA 均與先前凍結評估一致。entropy 權重依回合為 0.0102344、0.0123004、0.0125436、0.0121371、0.0104890、0.0114009。網路及近期 replay reward 非有限數值皆為零，buffer 皆為 50000/50000，三類 optimizer 欄位皆保存，critic-target L2 差距約 0.09–0.10。這些是有限摘要，沒有定位退步的根因，也無法證明更新過程一直穩定。

本輪選擇從弱風 Agent1100 另建有界分支，actor LR 由 3e-4 降至 1.5e-4，其他 SAC 選項沿用。預算額外400回合，到1500為上限，每100保存、maxAttempts=1，GPU同步6workers。候選意圖為檢查較小策略更新是否改善保持能力，尚未證明學習率是原因。原弱風1100→1500歷史可作觀察性對照，隨機續訓不構成相同樣本序列的控制實驗。

準備入口 trainingtools.prepare_sac_wind_slow 核對來源 run、GPU/worker、課程階段及精確 checkpoint SHA，透過既有恢復工具保存 lineage 和 guard。設定以保存狀態重建 SAC，既有工具核對權重、Adam狀態、entropy狀態與replay；遠端準備仍會實際執行檢查。已確認修改前本機沒有 MATLAB 訓練程序。

## 歸檔

R2024b隔離副本驗證完成，使用本機封存的原無風Agent1100及合成的Stage2狀態作測試fixture；未取得真正弱風Agent1100的MAT。先確認真實配方SHA拒絕此替代檔，再只在fixture改為其SHA，確認準備、磁碟重載、actor LR=1.5e-4、critic LR=3e-4、Stage2從1101、maxAttempts1、預算400、來源SHA保持及收據重複拒絕。腳本為artifacts/wind_actor_half_verify_20261107/verify.m，回報SLOW_PREP_VERIFY_OK。測試未訓練或模擬；遠端真實模型準備與長期穩定性仍待執行。

本機根目錄三份ZIP均已辨識並搬移，搬前搬後SHA一致，完整來源與目的地在各目錄 provenance.json。

| ZIP | artifacts/incoming 子目錄 | SHA256 |
|---|---|---|
| checkpoint-audit-20261107-002136.zip | sac-checkpoint-audit-20261107 | 8B9185C94DC1655288E60CDE930D852D21CB51589339F2751439416CE28D4175 |
| round3-paired-review-20261020-201402.zip | round3-paired-source-20261020 | AF5437F77A33C651330B626E54DC00DDAF5188620EB94821E2AD5BC7422AD0EF |
| sac-diagnostics-20261021-090503.zip | sac-diagnostics-source-20261021 | CA8687948F51C2226BD89C6FE6ABEA68578B4D292E6F7CCC2F111896B2C1D7EA |

前者為本次稽核，後兩者分別為第三組PPO配對與舊SAC診斷。output 下的簡報封裝與本次根目錄整理範圍分開，保留原位。
