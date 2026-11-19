# SAC replay 新路線結果與50回合接續決策

## 證據

根目錄 `sac-replay-holdout-20261119-200749-a922bbd3.zip`，35,561,301 bytes。SHA256 `e9b4a4ed38c25c359a12787342c34f327507f4e7b03290f3d22aec01ea4e21e8` 與使用者貼回遠端值相符；90個payload長度／SHA核驗，無重複ZIP項目或未列payload，安全路徑檢查後解壓。移至 `artifacts/incoming/sac-replay-holdout-20261119/`，移動後SHA相同，原來源路徑與收據見provenance.json。

review complete；兩模型SHA、關探索、權重未變、每模型40筆、2000011901–2000011920、兩風況、環境SHA與配對風皆核驗。純CPU sim，沒有訓練、回滾或升階。

| 模型 | 無風跑滿/20 | 弱風跑滿/20 | 無風mean steps | 弱風mean steps |
|---|---:|---:|---:|---:|
| 來源1600 | 18 | 18 | 2921.65 | 2923.8 |
| 500k1700 | 20 | 20 | 3000 | 3000 |

500k保留來源36個成功並救回4個失敗。弱風20次中17次實際抽到非零風／擾動，來源15/17、候選17/17。無風／弱風平均步數均高於來源，符合先前的來源減1跑滿數／95%步數參考篩選。

前10秒後相對原有限路線距離：

| 模型 | 無風平均RMS m | 弱風平均RMS m | 無風最差max m | 弱風最差max m | 跑滿且RMS≤10m、max≤20m 無風/弱風 |
|---|---:|---:|---:|---:|---:|
| 來源1600 | 8.999 | 9.533 | 50.814 | 50.636 | 3/20、0/20 |
| 500k1700 | 8.357 | 8.474 | 35.212 | 38.602 | 5/20、5/20 |

候選27/40情境RMS較低、29/40最大距離較低；來源失敗航次較短，這不是等時長精度配對。初始50m不含於此後段統計。只有10/40同時滿足描述性聯合精度條件，不稱全面精準或原升階過關。

兩批不同路線、同一候選合計80/80跑滿，來源70/80；不是80條獨立路線（40條×兩風況），不是多個訓練seed全面收斂證明。候選由先前路線挑選，新集只做一次檢查。與前輪50k/500k比較共同支持replay容量／保留方向，尚不能隔離資料年齡、取樣分布、更新次數等機制，更不代表移動目標追蹤已改善。

## 下一步

選擇 `20261119_004245_recovery_tpf24d3776/Agent_Final.mat`，episode1700、SHA `a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6`。建立獨立子run，最多新增50至1750、一次attempt、GPU同步6workers。actor1.5e-4／critic3e-4、500k容量與環境／課程不變，原run不動。新training seed20261120只是固定數值，不是日期排程或獨立複驗。

理由：來源buffer337132，50×3000最多150000筆，結束最多487132 <500000；100回合則可能覆蓋來源經驗。本輪先保持整個1700 replay內容，觀察繼續更新的效果，不同時改容量／LR。結束強制核對prefix完整、長度等於來源加新steps，異常停留paused而不自動再跑。下一輪若再延長須重新設計容量／保留策略，不能無限重複這個50回合條件。

guard window、checkpoint與顯示averageWindow因50回合段落設為50；課程快照的100回合條件與門檻不改。來源Stage2第700回合，最多到750，仍未達1000最低回合，不會升階。guard只有此有界段落，不宣稱可提前偵測所有退步。

完成後評估先前兩批共40 route seeds×兩風況=80次，保存完整新final、lineage、結果、軌跡與replay audit，自動打包並保持paused。評估集已被看過，僅作接續退步監控，不再叫新holdout。不自動選下一步、修改LR或回滾。

## 實作與驗證

- `prepare_recovery_training` 新增明確 `checkpoint_source=final`，必須指定SHA且限SAC有界、同LR／容量、不混其他pilot／critic／exploration變更。載入歷史核episode後，位元組複製已評估final到新child的Agent1700，避免假定另一份Agent1700序列化檔與final相同。舊checkpoint預設選擇不變。
- 修改前確認本機無MATLAB活動程序。真實337132 replay的500k1700在隔離來源準備通過：新起點SHA完全相同、history1700、budget50、checkpoint50、Stage2、STOP、無attempt；不允許同時改LR。未啟訓練／模擬，來源SHA不變。log `tests/output/final-extension-preparation.log`。
- 隔離假引擎驗證一次50回合、最多150000新steps、80配對評估、重入不重訓、中斷拒絕重啟；log `tests/output/replay-extension-flow.log`。PowerShell parser／隔離打包payload核驗／兩種摘要表通過。真實遠端GPU續訓尚未執行，不能以假引擎取代效能與收斂驗證。
- 圖 `holdout_results.png`、重算腳本與analysis.json在歸檔資料夾；圖已視覺核對。既有PPT未更新。

[遠端指令、看圖、取消與補包](../guides/sac-replay-extension-2026-11-19.md)
