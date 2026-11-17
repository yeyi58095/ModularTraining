# Actor 短對照後診斷交件 — 2026-11-17

根目錄 `sac-actor-pilot-probe-20261117-140452-85b7904a.zip` 已核驗並歸檔至 `artifacts/incoming/sac-actor-pilot-probe-20261117/`。ZIP SHA256 `ae4528b7f9db3a8607df437eecceeb0a747ac5676a64bd9575a4f2f5dfd3548d`，20個manifest payload長度／SHA全部通過，移動前後ZIP SHA一致。使用者本次未提供遠端外層SHA，不能稱已做遠端外層比對；內含manifest已核對。原路徑、目的地、hash記於provenance.json。

`review.status=complete`、launcher.error=null。此次為唯讀推論，沒有新增訓練回合或模擬飛行。四份checkpoint狀態／共同輸入／動作Q報告的SHA互相一致，1600對上前次recovery.child_checkpoint_sha256，1700對上前次實際凍結evaluation的final SHA。source_unchanged／weights_unchanged皆為true。

## 共同輸入與結果

MATLAB只載入兩份shared-inputs.mat（不載入agent），`isequaln`確認第一組256 transitions逐項完全相同；第二組不同，跨臂不混比第二組摘要。以下Gaussian統計皆使用第一組中第65–256點，為動作變換前參數，不是實際roll命令或飛行輸出。

| 項目 | 來源1600 | 基準1700 | actor半速1700 |
|---|---:|---:|---:|
| Actor LR | 基準1.5e-4／半速7.5e-5 | 1.5e-4 | 7.5e-5 |
| Entropy α | 0.0107455 | 0.0153073 | 0.0131247 |
| α相對來源 | — | +42.45% | +22.14% |
| Gaussian mean絕對值平均 | 0.32225 | 0.56250 | 0.62462 |
| 與來源逐輸入mean差的絕對值平均 | 0 | 0.56496 | 0.53254 |
| Gaussian std平均 | 0.16172 | 0.25728 | 0.18491 |
| 記錄動作Q1平均 | 72.6720 | 75.7897 | 73.8139 |
| 記錄動作Q2平均 | 72.9497 | 76.2815 | 73.6189 |

兩份1600的第一組推論結果相同。半速確實生效，但策略映射仍明顯變動；其逐輸入mean差略小，不能用mean絕對值較大就說半速策略漂移更大。這些是少量歷史輸入的描述統計，不是完整狀態分布的距離或LR因果檢驗。

在相同16個觀測×33個動作網格上，以min雙Q的網格argmax計，基準13/16、半速15/16與來源不同。網格峰值變動可能受近似平坦曲線影響，不能當實際最適動作或Q高估證明。此處沒有Monte Carlo return、TD error或已定位失敗時刻的反事實控制試驗。

所有已檢查actor、critic及target網路參數無NaN／Inf；replay兩者皆保存50,000。actor／critic／entropy optimizer字段皆存在，但字段存在不等於已完整證明所有optimizer數值及歷程均被保留。最近10,000筆replay terminal markers由來源4變成基準7／半速5，這是不同訓練樣本，不能當配對飛行失敗數。

## 判斷與接續

結合前次凍結結果（來源38/40、基準11/40、半速7/40），本次仍不支持延長任何1700分支。沒有數值爆炸證據，也沒有證明entropy上升或critic高估是根因。降低actor LR並未保留固定策略能力，但不代表已排除所有策略更新因素。

本輪診斷到此先收斂：保留1600作凍結基準，全部分支保持paused，不再要求使用者重跑同類probe或直接再降LR。現有交件已含飛行軌跡，若要繼續機制分析，應從已收集的配對失敗軌跡定位輸入、指令及距離變化，優先使用現有資料；不為取得同類摘要再消耗遠端訓練。

新訓練仍須提出能區分結果的具體假設，先定單一變因、有限預算與凍結驗收。若沒有這項依據，meeting先討論任務／reward與控制品質指標，而不是無限掃LR。現在沒有新retry指令，也不跳Stage3或放寬終止條件。

這次未修改已交付的20261119 PPT；該22頁版本的資料截止為前次actor pilot分析，後續診斷結果以本紀錄補充，避免把新發現冒稱已納入PPT。
