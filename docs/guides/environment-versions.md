# 環境版本與遠端更新

2026-10-15。Agent 定義、Simulink 環境、課程分開管理；環境選版不代表 reward 候選已部署。使用者後續授權 commit/push；遠端由使用者依指令操作，代理不自行連線更新或啟動訓練。

## 現在的結構

```text
+trainingmodels/ppo_lstm128/       Agent 架構與 PPO profile
environments/spatial_v1/
    environment.json              環境 id、模型檔名、相依檔與 SHA256
    FAFA_Simulation.slx            正式空間循跡；原 reward
runtime/                          共用引擎與 supervisor
    FAFA_Simulation.slx            保留給舊工具／直接執行的相容檔
experiments/progressive_v2/
    curriculum.json               schema 2；指定 model 與 environment
    assets/
    runs/<實驗>/
        environment.json          本次實驗固定的環境 manifest
        environment/              SLX 與列出的相依檔副本
        curriculum.json           課程快照
        model.json                Agent 設定
        checkpoints/
        attempt_*/environment_used.json  本次預檢模型／引擎 SHA
```

`spatial_v1` 是目前已部署的空間循跡環境，模型 SHA 為 `495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be`。`spatial_reward_v2` 尚未發布；離線 reward 候選不會因架構更新就進入訓練。

環境 manifest 只接受明列的同層 `.slx/.mat/.m/.sldd` 檔及 SHA256，拒絕路徑跳脫、重複名稱與保留的訓練檔名。現有 spatial_v1 的正式模型是自包含 SLX；日後需要額外資產必須列入 manifest。引擎目前只支援 FAFA_Simulation 的既有 observation/action 介面，不代表可直接換成任意 Simulink 模型。

新的 run 預設選 spatial_v1，或使用 `retry(environment="版本id",...)`；schema 2 課程的 environment 與入口參數必須一致。schema 1 課程仍可讀，新建 run 時使用明確指定的環境或預設 spatial_v1。續訓禁止傳入另一個 environment。

## 遠端：先保留，再更新

使用者已確認遠端停止或暫停。仍由工具在操作當下檢查 status 與排他鎖。以下在遠端執行，不需將 checkpoint 搬回本機。

**第一步：只先把 `preserve_training_environment.ps1` 複製到遠端。不要先更新／覆蓋 runtime。** 腳本可獨立執行，不依賴新版 MATLAB 程式。每個未來需要續訓的舊 run 都要各自保存。

若目標 run 最後使用的是已核對的正式空間循跡模型，在 PowerShell 執行（替換實驗路徑）：

```powershell
$session = 'D:\你的遠端專案\experiments\progressive_v1\runs\你的實驗ID'
.\preserve_training_environment.ps1 -SessionDir $session `
  -ExpectedModelSha256 '495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be'
```

此 SHA 只適用於這個已知模型。若不符，腳本會拒絕，應先核對遠端 SLX 與最後實驗紀錄，不要為了通過就換上本機 SLX。保存的是**更新當下遠端檔案**，不是證明整段歷史都在同一環境跑過。若更新已發生，必須從可信備份找回並核對原檔，不能把新環境冒充舊環境。

腳本從該 run 的 control.scriptDir 找當地來源，保存 SLX，以及 runtime 同層的 MAT／資料字典；額外同層 MATLAB 相依檔可用 `-AdditionalFiles 'helper.m'` 指定。一般 checkpoint 不在 runtime，且 Agent*.mat 不允許當環境資產。

它會逐檔比對來源、目的 SHA，最後才發布 environment.json。不移動 run，不改 control、課程、checkpoint、STOP、guard 或歷史。相同副本可重跑驗證；不同內容拒絕覆寫；中斷留下 environment.preparing 時要求先檢查，不自動清除。

**第二步：所有要保留的舊 run 保存完成後，再同步新版程式。** 確認遠端儲存庫已包含本次提交後，使用既有 Git 更新流程；不要同步生成的本機 runs 或覆蓋遠端訓練資料。可以先 git fetch 取得提交、僅抽出保存腳本到暫存目錄，完成保存後才 fast-forward 工作目錄；fetch 本身不更新 runtime。

**第三步：遠端 MATLAB 根目錄先預檢舊 run。**

```matlab
sessionDir = "D:\你的遠端專案\experiments\progressive_v1\runs\你的實驗ID";
[modelFile, manifest] = trainingenv.resolve(sessionDir); % 唯讀驗證
disp(manifest.id)
disp(modelFile)
info = retry(resume=sessionDir,start=false);            % 更新控制路徑，不啟動
```

預檢不解除 guard 暫停。只有決定正式續訓時才執行 `retry(resume=sessionDir)`；這不是本次要自動執行的步驟。已有 Agent_Success 的完成 run 不透過 retry 再訓練，仍可用 resolve 檢查環境。

舊 run 沒有 environment.json 時，新的 retry／attempt 拒絕猜測並提示先保存環境。沒有 status.json 的舊 start=false 草稿不能由保存工具認定已停訓；若沒有 checkpoint，改用新版重新建立草稿即可，不需冒充有訓練歷史。

## 遠端的新 progressive_v2

```matlab
inputs = prepare_progressive_v2_training();
cfg = jsondecode(fileread("configs/lab_gpu6_progressive_v2.json"));
args = namedargs2cell(cfg);
info = retry(args{:}); % 設定內 start=false，只建立草稿
[modelFile, manifest] = trainingenv.resolve(info.sessionDir);
```

課程目前選 spatial_v1，仍使用原 reward；reward 校準與正式部署另行處理。每次 retry 新建都產生另一個 run，請保存 sessionDir。續訓會使用這個 run 的快照，而不依賴 registry 或 runtime 中的 SLX 後續是否改動。

## 評估、恢復與限制

- 已綁定 run 的 compare_training_checkpoints 使用其環境快照，必要時將所有列出的資產複製到評估暫存資料夾。沒有綁定的舊 run 保留既有唯讀診斷功能，但報告明列 `legacy_current_runtime_not_historical_proof`，不能當歷史環境重現。
- 已綁定父 run 的 prepare_recovery_training 繼承環境快照；配方要求另一個 SLX SHA 時拒絕，不暗中換環境。舊未綁定父 run 的既有恢復配方仍保存 prepare 當下 runtime 並明列來源，不回寫父 run。
- 環境快照固定 SLX 與列出資產；**共用 engine、課程引擎、MATLAB／工具箱版本並未全部封存**。每次 attempt 在 guard／engine 前記錄當下 engine SHA，guard 暫停時不代表已執行 engine。這不是整台電腦的完全可重現映像，也不會保留 optimizer 私有狀態的額外解讀。
- 本次不提供自動跨環境 checkpoint 移植，也不修改活動實驗的課程快照。要改 reward 或任務規則，應另發布環境版本並建立明確的新實驗。
- 保留 runtime SLX 是遷移相容安排；直接跑 training_engine.m 的舊方式仍可能使用它。正式實驗應走 retry／checkpoint_attempt，才能取得環境綁定與驗證。

## 本機驗證

通過 MATLAB 新建／續訓、schema 1/2、課程快照、跨位置環境讀取、雜湊改動拒絕、未知版本／路徑跳脫拒絕、實際 attempt 假引擎接線；既有課程、相對路徑、課程工作區及 recovery guard 測試亦通過。

PowerShell 合成測試通過來源保存、MAT 相依檔、重跑、活動狀態拒絕、排他鎖拒絕、錯誤 SHA、路徑跳脫與副本被改動拒絕。另用測試恢復副本完成 CPU 五步純 sim，確認 evaluator 使用 run_snapshot、權重與來源 SHA 不變。沒有連線更新遠端，也沒有 GPU／多 worker 正式驗證。
