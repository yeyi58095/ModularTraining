# 1600／1700診斷與下一個有界試驗

使用者交回`sac-child-probe-20261116-121523-d59ff383.zip`，已移`artifacts/incoming/sac-child-probe-20261116/`，原始／目的路徑與SHA見provenance。ZIP SHA256 `62C9D8954DF7418459D6E72C5FDDDC8630503B3CA91DF4F4F7AA15E3A2C5BAE3`，搬前後相同，11個payload大小及SHA通過；無另附遠端SHA，不宣稱獨立核對遠端整包雜湊。

來源為新child `20261114_211021_recovery_tp4c32126b` 的1600（45e57d...）與1700（9f1add...），與已知凍結報告來源吻合。report complete、source_unchanged及各序列weights_unchanged均成立。

- alpha 0.0107455→0.0109984，約+2.35%，沒有熵係數突然爆增的證據。
- actor／雙critic／target網路皆無非有限數值，optimizer／PolicyState存在，replay兩者皆50000；critic-target L2差距沒有擴大。這不代表critic準確或訓練必然穩定。
- 兩份共同輸入都是各模型近期replay內一個跑滿3000步episode的前256步，非定位到的失敗軌跡。第一prefix在第65–256步，Gaussian mean絕對值平均0.3223→0.6806，std平均0.1617→0.1214；第二prefix mean絕對值反而0.5517→0.3064，std0.1452→0.1274。支持輸入相同時策略改變，不支持全域動作必然變大。
- 16個第一prefix觀測×33動作的min雙Q網格峰值有變化：1600較常偏正端，1700多數偏負；同時Gaussian mean也改變。這是有限off-policy樣本，不是真實回報、TD誤差或Q高估證明，不能據此確診actor或critic為唯一根因。

使用者要求推進到直接可執行指令。本次選擇**短、帶同起點基準的單因素actor LR假說試驗**，而不是從2100長跑或聲稱找到修復。兩個新分支都從同一1600初始化，基準actor1.5e-4、候選7.5e-5，其他學習設定不改；各最多新增100回合即停、凍結評估原診斷與另一批固定路線。新基準能區分本次隨機波動，不能僅拿歷史1700當公平對照；同seed不保證相同噪音時序，等episode不等於等環境步數或更新數。兩臂各一次不構成因果、穩定性或收斂證明。

試驗選actor LR是為了檢驗較小策略更新是否保留已觀察到的能力，不是由Q變化推出的根因結論；critic／entropy／replay與課程保持。未在本機正式訓練、未遠端連線。若後續同條件基準與候選都退步，停止這個方向的盲目延長，保留1600並重新檢查假說。

操作與保護邊界見[短對照試驗](../guides/sac-actor-pilot-2026-11-16.md)。
