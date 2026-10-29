# SAC random-route wind curriculum v1

分組入口：[paper_reference](groups/paper_reference/README.md)。

全新 SAC64 前饋模型，參考 Dally2022；不是雙SAC串級飛控復現。沿用 spatial_v2、10維觀測／1維橫向命令、reward、50m終止語意與3000步上限。首回合即隨機路線，每回合更換。

| 階段 | 東／北風分量，各自抽整數 m/s | turbulence等級 |
| --- | --- | --- |
| random_calm | 0 | 0 |
| random_weak_wind | [-1,1] | 0 |
| random_moderate_wind | [-2,2] | [0,1] |
| random_full_wind | [-3,3] | [0,2] |

最大水平風速為分量合成，最後階段可達sqrt(18)約4.24m/s，不是3m/s。turbulence是既有模型的等級值，不是m/s或新增陣風模型。後期仍抽到弱風，不清空前階段replay；所有階段沿用同一agent。

路線使用既有生成器：15m/s、70m高度、起點[50,0,70]與既有初始方向；直線150–500個0.1秒步（約225–750m），轉角目標40–80度，轉率pi/32 rad/s（名義半徑約153m），4000點約6km。沒有隨機高度／起始方向，也沒有排除自交；這些是幾何限制，不是已證明每條路線均飛得過。3000步不代表完成整條路線。觀測已有d、d_dot、heta、kt，但未證明對所有未見路線充分可觀測。

模型：兩層64單元、LayerNorm、ReLU、Glorot、獨立雙Q、Gaussian mean／softplus std；buffer50k、batch256、gamma.99、LearningFrequency1、NumEpoch1、MaxMiniBatchPerEpoch1。actor／critic／entropy固定LR3e-4取自論文高度設定；**不使用姿態控制器4e-4線性降零排程**。64寬度取姿態設定，std正值轉換、10Hz與暖機1000步保留本實作選擇。這是整套候選，不能分離單一設定因果效果。

R2024b OffPolicyTrainer實作核對：parallel在episode結束收到經驗後計算更新批次，正LearningFrequency參與outer epoch數量計算。Frequency1是預期每筆新經驗一次更新的配方，不是每個worker即時更新；暖機與停止時點仍影響實際更新數。比原Frequency32有更多學習工作，不保證速度提升。

每stage至少1000回合，100回合窗口連續3窗reward>=2200、steps>=2800、滿3000步率>=90%；每stage上限5000回合，總上限20000（最多6000萬互動步）。這是明確有上限的可行性配方，首段只500，並非授權一次跑完全部預算。

達訓練條件後，額外要求固定5個驗證路線seed，當前stage及無風stage皆關探索跑滿；後10秒獨立原路線max<=20m、RMS<=10m。這些是本次新設的驗收門檻，非論文標準，也未放寬原50m終止閾值。驗證集用於升階，不宣稱完全未使用的最終test set或全面穩健。

訓練route seed範圍1..1e9；驗證seed2000000101..2000000105。每worker回合的seed記於runs/r*/route_seeds.csv，風另記wind_all.csv；worker本地回合不直接等於全域訓練回合。生成器版本與DT必須一起保留才能重建；seed不保證內部湍流時序或平行訓練完全可重現。

預設GPU、同步6 process workers、minWorkers6、無自動降worker備援、每100保存、每attempt500、maxAttempts1、v7保存。首次prepare不啟動訓練。

[遠端操作、監看、畫圖與暫停](../../docs/guides/sac-random-route-2026-10-29.md)
