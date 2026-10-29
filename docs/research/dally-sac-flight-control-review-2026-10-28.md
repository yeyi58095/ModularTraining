# Dally & van Kampen 2022 本機全文閱讀

日期：2026-10-28。來源 `D:/daniel/GradSchool/0-Beginner/Paper/2202.09262v1.pdf`，20頁，arXiv v1，2022-02-16；SHA256 `ebb8d462cea989396431fb249a9b0f75afe64ec4dce8761b99e4bbce5e9a2da6`。原檔未搬移或修改。讀取全文文字，另渲染核對第7–9及18頁的架構、參數、訓練曲線與可靠度。本文版本未與AIAA出版版逐字比對。

## 最重要的發現

- 第9頁明說訓練後期仍有顯著性能下降，會重複訓練直到得到滿意策略。Fig.6為成功試驗中的5個random seeds，顯示20-window平滑均值及四分位範圍，不是所有試驗的無篩選結果。
- 第18頁IV.D.2：27次串級SAC控制器配對訓練試驗，按Fig.8標稱高度追蹤任務、5% nMAE門檻計，成功率26%。這是訓練成功率，不是部署飛行成功率，也不能直接套作本專案機率。
- 因此本文支持區分「成功訓練出的控制器性能」與「訓練流程可靠度」。它沒有證明本案退步的根因，作者對隨機初始化／抽樣的歸因也不是本案機制診斷。

## 任務與架構（第5–9頁）

- Cessna Citation 500高擬真非線性模擬，模型根據PH-LAB飛行資料建立。本文結果不是實機飛行驗證。
- 100Hz控制；外部PID auto-throttle控制空速，另有yaw damper及致動器低通／飽和。
- 內迴路SAC追蹤pitch、roll、sideslip；9維觀測為3個加權追蹤誤差、3個當前控制輸入、p/q/r；3維動作為升降舵、副翼、方向舵增量。增量範圍按致動器限制的百分之一選擇。
- 外迴路SAC追蹤高度，2維觀測為加權高度誤差及當前pitch reference，1維動作為pitch reference增量；限制對應pitch reference rate不超過10deg/s。
- 先訓練內迴路，再用已訓練內迴路訓練外迴路。兩者各約1e6互動步；內迴路500個20秒episode，每步0.01秒。不是用episode數直接對照本案0.1秒／最長3000步。
- reward以裁切後的加權追蹤誤差為基礎；本文v1式15/21的clip上下界寫法值得和作者程式核對，不能未核對即抄成新reward。姿態誤差權重為6/pi乘[4,1,1]，高度為1/240。

## Table 1及網路

| 設定 | 高度SAC | 姿態SAC |
|---|---|---|
| 前饋隱藏層 | 32×32 | 64×64 |
| learning rate | 3e-4 | 4e-4線性下降至0 |
| target entropy（依表列值） | -1 | -3 |
| gamma | 0.99 | 0.99 |
| replay容量 | 50000 | 50000 |
| minibatch | 256 | 256 |

使用ReLU、Layer Normalization、Xavier初始化、Adam；未使用LSTM。評估將Gaussian取樣噪音設零。表中tau=0.995在Algorithm 1乘舊target，新網路係數為0.005；不可把0.995直接當MATLAB TargetSmoothFactor。本案build_sac明確設TargetSmoothFactor=0.005。

本機sac_mlp128定義為10維觀測／1維動作（由build_sac契約），sampleTime0.1、gamma0.98、minibatch64、buffer100k、learningFrequency32、NumEpoch1／MaxMiniBatchPerEpoch1。原始actor5e-5／critic1e-4；最新慢critic分支actor1e-5／critic2e-5。這是目前程式／配方對照，不替代歷史run快照。論文Algorithm 1每步寫一次更新；實際warmup／更新排程仍需作者程式核對，不能僅由偽碼宣稱與MATLAB實際更新量精確相差32倍。

## 驗證與限制（第10–19頁）

- 成功策略在標稱高度／roll／sideslip任務nMAE2.64%；不是路線距離誤差2.64%。
- 測試六種故障、感測偏差與噪音、垂直陣風、不同初始高度／速度及參考波形。
- 主要robust response中權重不變；文中online robust adaptation指固定策略對狀態變化的反應，不是飛行中持續梯度更新。
- 額外adaptive response為對每種故障模型另作離線訓練後的控制器，非當場在線訓練證明。六種故障中五種重新訓練後相同或更差。

## 對本案的建議（尚未實作）

優先建立獨立訓練seed的成功率、互動步數及凍結checkpoint能力保留評估，完整呈現失敗試驗。可再唯讀稽核觀測是否包含動作所需狀態、動作尺度／變化率、輸入正規化及實際更新比例。本文支持研究這些設計，不能據此直接加大LR、縮buffer、換增量動作或改終止門檻。沒有啟動訓練、修改runtime或既有run。
