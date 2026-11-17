# 探索開／關交件與 replay retention 下一步 — 2026-11-18

根目錄 `sac-pilot-exploration-20261118-001036-09b4ec44.zip` 已核對39個manifest payload長度／SHA並歸檔至 `artifacts/incoming/sac-pilot-exploration-20261118/`。ZIP SHA256 `6d8ce3b69e26c0466289c307790dd1974faba263fe9947b2bc854c333804c7f7`，搬移前後一致，provenance保留原路徑。使用者未提供遠端外層SHA，不冒稱外層跨機SHA已配對。

`review.status=complete`，三模型各8次新CPU模擬完成。逐列核對off/on模型SHA、環境／課程／runtime／random-path hash、guidance variant、seed與實際風參數一致，on皆weights_unchanged、use_exploration=true、std scale=1。comparison.json數字與原始評估相符。

| 模型 | 關探索跑滿 | 開探索跑滿 | 關探索平均步數 | 開探索平均步數 |
|---|---:|---:|---:|---:|
| 來源1600 | 8/8 | 8/8 | 3000 | 3000 |
| 基準1700 | 0/8 | 0/8 | 710 | 707.75 |
| 半速1700 | 3/8 | 1/8 | 1692.125 | 904.875 |

無任何off失敗被on救回，半速有兩筆off跑滿改為on失敗。on的15筆失敗皆有distance_threshold證據。基準多數失敗步數相近，開探索未恢復能力。這些是失敗挑選的四seed×兩風況，每情境僅一條抽樣rollout，不能宣稱已排除所有探索效應或得到泛化成功率；但不支持以關探索解釋本批主要失敗。仍未證明critic高估、entropy或actor LR為根因。

## 改做可檢驗的經驗保留試驗

來源replay長度與容量50,000，前次兩臂100回合新增236,074／249,328個環境步，分別為容量4.72／4.99倍。這是換入新資料的規模，不是已量測的gradient次數或精確抽樣頻率。候選假說：續訓期間快速替換舊經驗，可能使保持既有能力所需的資料不再可抽樣。

新的 `-ReplayPilot` 從同一來源1600分別另建baseline50k及retained500k，actor1.5e-4、critic3e-4、entropy與更新頻率、batch、環境／課程、GPU／六workers均沿用。只變replay容量50k對500k，各最多新增100回合。兩臂同請求training seed20261118，但策略、軌跡及互動步數／實際更新量仍可能不同。

500k容量高於原50k加名目100×3000=300k的新transition總量，為來源資料保留留出空間；不依此算式代替實測。腳本準備後與訓練結束後逐筆比較原50k是否仍為最舊chronological prefix；大buffer若不保留則標示試驗無效並停止，不繼續自動工作。prefix=false只說不再完整保留於前綴，不能當成零重疊證明。

原resize_sac_replay已保留權重、Adam狀態、PolicyState及replay時序；本次重用，沒有改正式runtime、reward或課程。舊LSTM大buffer試驗未成功，不能將本次假說稱為已知修復；這次針對paper64的同來源兩臂並直接量測保留，單次結果仍無法完全分離資料保留、抽樣比例與其他隨機因素。

## 評估及預先判讀

來源及每臂完成後皆凍結、關探索評估原診斷10seed2000011501–1510，加新10seed2000011801–1810，各無風／弱風，共40次；整套120次凍結飛行＋最多200新增訓練回合。新路線先固定，不事後挑選。

`screening.json`為初步可行性篩選：大buffer各stage跑滿數不得比來源少超過1/20，平均步數至少來源95%，並且總跑滿數高於本輪新50k基準。門檻只供本試驗是否值得再複驗，不是原升階門檻、顯著性檢驗或續訓授權；仍需逐看新路線子群與距離品質。無論pass與否，兩臂都paused，不自動延長或進Stage3。

- 基準退步、大buffer保留資料且保住能力：支持容量／歷史資料利用是值得複驗的介入方向，尚不能稱根因確診。
- 兩者退步且大buffer確實保留原資料：單靠保留這50k不足，停止盲目增加容量。
- 兩者都保住能力：此seed未重現退步，不能說大buffer優於基準。

## 驗證與限制

- 隔離假引擎：舊actor模式與新replay模式皆完成兩臂×100及三份40次評估報告，完成後不重開，中斷意圖拒絕。相同結果不會被screening判為改善或續訓。
- 真實封存paper64：50k→500k resize、保存／再載入及300k合成append後，原50k完整保留；50k組的替換可被audit偵測。沒有train/sim。
- 真實來源的準備測試：兩配方子run的網路、optimizer moments、alpha、原replay及trackerIDs保留，Stage2、100回合guard及STOP存在，未啟動。僅測試來源的control使用隔離群組，不修改正式run。
- PowerShell5.1解析、隔離打包及payload SHA通過。遠端六worker實際試驗與長期效益尚未驗證。

下一步：[遠端續訓指令與取消方式](../guides/sac-replay-retention-2026-11-18.md)。這次不修改既有PPT；新結果與設計保存在本紀錄。
