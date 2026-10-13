# 第二版末端目標修正與續訓

2026-10-12 使用者授權正式部署、push 及提供續訓指令。正式 runtime/FAFA_Simulation.slx 的 guidance 採用實驗室已評估的 endpoint_lookahead_v2 原碼；reward、IsDone、planner、課程與 optimizer 不變。這是環境變更，不能將前後分數差異全歸因於學習。

實驗室 Agent21600：第二版既有 seeds201:210 的 Stage4/5 共20次、新 seeds211:220 共20次、前三階段 seed101 共3次，全跑滿3000步；另外原版新情境20次也全部完成。新情境小風平均reward原版2917.28、第二版2995.42，平均observation7 RMS 0.22024、0.21226。Stage5 抽樣包含零風案例，不代表全是非零風。最差距離仍接近46m；Stage6尚未驗證，不能宣稱整體合格。評估報告為使用者實驗室輸出，本機未執行21600checkpoint。

新配方 configs/recovery_21600_endpoint_v2.json 從21600接續，actor LR保持2.5e-5，每段100，新增預算10000（最多31600），保留退步保護。繼承原課程Stage5進度，不因評估通過而跳階；提前課程完成、退步或其他暫停條件仍可能先停止。硬體沿父control（原目標6workers/GPU），不是本機驗證此組合。

先確認實驗室沒有活動訓練／評估。PowerShell：

```powershell
cd D:\daniel\ModularTraining
git pull --ff-only
```

MATLAB：

```matlab
cd D:\daniel\ModularTraining
clear prepare_recovery_training retry
rehash
if bdIsLoaded('FAFA_Simulation'), close_system('FAFA_Simulation',0); end
root=fileparts(which('retry'));
parentSession=fullfile(root,'experiments','progressive_v1','runs', ...
    '20261010_224522_recovery_tpc1c4f06e');
next=prepare_recovery_training(parentSession, ...
    fullfile(root,'configs','recovery_21600_endpoint_v2.json'));
info=retry(resume=next.sessionDir);
disp(info.sessionDir)
```

只執行一次 prepare；它每次建立新分支。後續查進度用 info.sessionDir。不要解除舊run的guard或從舊run直接retry。prepare 保留父checkpoint並記錄新環境SHA與繼承關係；純評估未消耗或增加訓練回合。課程快照、父實驗和checkpoint不覆寫。

正式環境預設評估不再傳 guidanceVariant；baseline 指當前來源SLX。舊版A/B應使用歷史版本的獨立副本，禁止將舊版runtime覆蓋到活動訓練中。tests/fixtures/guidance_before_endpoint.m.txt 僅供幾何回歸，不是可續訓模型。

本機驗證已通過：正式chart與已評估v2原碼相等、末端及邊界幾何、重複套用拒絕、110步CPU純sim、WindowManager初始化、實際短測checkpoint的分支權重/來源保留與假引擎預算暫停。未在本機啟動正式訓練或GPU/6workers測試。SLX其他差異僅視窗開啟狀態與存檔版本/metadata。

使用者預計五小時後檢查一次、之後兩天不使用電腦。此次預算是回合數，不保證五小時跑完，也不自動在五小時停訓；到預算或guard暫停就保留結果等待人工判讀，不自動另開分支。保持實驗室主機供電、不休眠；五小時後可讀取status及最新日誌，不必停訓評估。
