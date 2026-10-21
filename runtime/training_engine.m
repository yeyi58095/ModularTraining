% 共用訓練引擎：套用 overrides、建立／載入 PPO agent，連接 Simulink 環境與實際 workers。
% 以 train 執行本段，定期保存 checkpoint，段末先保存歷史再判定 guard／課程；由 attempt 在新程序執行。
%% LSTM-PPO parallel training with periodic checkpoints (R2024b)
% Run the WHOLE script in a fresh MATLAB session.
% Native crashes cannot be caught; periodic checkpoints protect completed work.
% Resume preserves training statistics/episode numbers in the same experiment folder.
clc;
warning('on', 'all');

%% User settings
% 本段可設定的預設值；attempt 僅覆蓋白名單參數。
resumeAgentFile = ""; % Full path to Agent100.mat or Agent_Final.mat; "" = new
numWorkers = 6; % Original script's intended local pool size
minWorkers = 1;
executionMode = "parallel"; % Legacy runs retain their original dispatch.
checkpointEvery = 100;
maxEpisodes = 50000; % Additional episodes in this invocation when resuming
trainingDevice = "gpu"; % For a NEW agent; use "cpu" if no supported GPU is available
showPathFigure = false;
fastRestart = "on"; % Diagnostic option: try "off" if native crashes recur
disableTrainingLogging = true;
disableUAVAnimation = true;
targetReward = 2900;
averageWindow = 50;
trainingPlots = "training-progress";
baseSeed = 0;
closePoolOnExit = true;
outputRoot = "";
poolDiagnosticDir = "";
agentFactory = [];
agentValidator = [];
curriculumContext = [];
environmentModelFile = "";
% Entrypoint/automatic supervisor supplies only these known settings.
% 僅接收已知 overrides 欄位，避免入口把任意設定注入引擎。
if exist('checkpointOverrides', 'var') && isstruct(checkpointOverrides)
    allowed = {'resumeAgentFile','numWorkers','minWorkers','checkpointEvery','maxEpisodes', ...
        'trainingDevice','fastRestart','targetReward','averageWindow', ...
        'trainingPlots','baseSeed','closePoolOnExit','outputRoot','poolDiagnosticDir', ...
        'agentFactory','agentValidator','curriculumContext','environmentModelFile','executionMode'};
    for settingIndex = 1:numel(allowed)
        settingName = allowed{settingIndex};
        if isfield(checkpointOverrides, settingName)
            eval([settingName ' = checkpointOverrides.(settingName);']);
        end
    end
end
validateattributes(numWorkers, {'numeric'}, {'scalar','integer','positive'});
validateattributes(minWorkers, {'numeric'}, {'scalar','integer','positive','<=',numWorkers});
validateattributes(checkpointEvery, {'numeric'}, {'scalar','integer','positive'});
validateattributes(maxEpisodes, {'numeric'}, {'scalar','integer','positive'});

scriptDir = fileparts(mfilename('fullpath'));
cd(scriptDir);
runRoot = fullfile(scriptDir, 'training_runs_parallel_checkpointed');
if strlength(string(outputRoot)) > 0, runRoot = char(outputRoot); end
if ~isfolder(runRoot), mkdir(runRoot); end
[~, runTag] = fileparts(tempname(runRoot));
% 載入實際 episode 歷史；禁止向同一 run 較舊 checkpoint 回退而覆寫新進度。
resumeHistory = [];
resumeEpisode = 0;
if strlength(string(resumeAgentFile)) > 0
    [resumeHistory,resumeEpisode,saveDir] = checkpoint_resume_state(resumeAgentFile);
elseif strlength(string(outputRoot)) > 0
    saveDir = char(outputRoot);
else
    saveDir = fullfile(runRoot, [char(datetime('now','Format','yyyyMMdd_HHmmss')) '_' runTag]);
end
if ~isfolder(saveDir), mkdir(saveDir); end
if isfile(fullfile(saveDir,'Agent_Success.mat'))
    error('Checkpoint:AlreadySucceeded','This experiment already has Agent_Success.mat.');
end
checkpointDir = fullfile(saveDir,'checkpoints');
% Refuse rollback into a folder that already has newer numbered checkpoints.
existingFiles = [dir(fullfile(checkpointDir,'Agent*.mat')); dir(fullfile(saveDir,'Agent*.mat'))];
for fileIndex = 1:numel(existingFiles)
    number = regexp(existingFiles(fileIndex).name,'^Agent_?(\d+)\.mat$','tokens','once');
    if ~isempty(number) && str2double(number{1}) > resumeEpisode
        error('Checkpoint:RollbackWouldOverwrite','A newer checkpoint exists; resume that checkpoint instead.');
    end
end
existingFinal = fullfile(saveDir,'Agent_Final.mat');
if isfile(existingFinal)
    finalEpisode = 0;
    try
        [~,finalEpisode] = checkpoint_resume_state(existingFinal);
    catch historyError
        warning('Checkpoint:OldFinalUnreadable','%s',historyError.message);
    end
    if finalEpisode > resumeEpisode
        error('Checkpoint:RollbackWouldOverwrite','Agent_Final.mat contains newer progress; resume it instead.');
    end
end
runLogDir = checkpoint_run_log_dir(saveDir);
fprintf('Training output folder: %s\n', saveDir);
if strlength(resumeAgentFile) > 0 && ~isfile(resumeAgentFile)
    error('Training:MissingCheckpoint', 'Checkpoint not found: %s', resumeAgentFile);
end


%% Environment Setup
% 重設 client 回合／路徑顯示狀態，供本段環境初始化。
global episodeCounter pathFigure wind_setup TARGET_SPEED DT WAYPOINT_SPACING
episodeCounter = 0;
wind_setup = [];
pathFigure = [];
if showPathFigure
    pathFigure = figure('Name', 'Path Display', 'NumberTitle', 'off');
end

%% Global Trajectory Parameters
% 共用速度、取樣時間與點距；移動 window 的速度需與路徑速度一致。
% Keep the moving window speed consistent with the target speed:
% WAYPOINT_SPACING = TARGET_SPEED * DT
TARGET_SPEED = 15;      % Target speed (m/s)
DT = 0.1;               % Sample time (s)
WAYPOINT_SPACING = TARGET_SPEED * DT;

%% Observation and Action Space Definition
% FAFA 介面契約：10 維觀測、1 維 [-1,1] 橫向命令。
obsDim = [10 1];
obsInfo = rlNumericSpec(obsDim);
obsInfo.Name = "observation";
obsInfo.Description = ["P_E_norm";
                       "P_N_norm";
                       "phi";
                       "psi";
                       "p";
                       "r";
                       "d";
                       "d_dot";
                       "heta";
                       "kt"  ];

actDim = [1 1];
actInfo = rlNumericSpec(actDim);
actInfo.Name = "action";
actInfo.Description = ["lat_cmd"];
actInfo.LowerLimit = [-1];
actInfo.UpperLimit = [1];

%% Simulink Setup
% 載入正式模型並建立 RL 環境，不將臨時 logging 設定保存到 SLX。
modelName = "FAFA_Simulation";

% Do not save changes to the original model.
if strlength(string(environmentModelFile))==0
    environmentModelFile=fullfile(scriptDir,modelName+".slx"); % Legacy direct script use only.
end
addpath(fileparts(environmentModelFile),'-begin');
cd(fileparts(environmentModelFile));
loadEnvironmentModel(environmentModelFile);
if ~strcmp(get_param(modelName, 'SimulationStatus'), 'stopped')
    error('Training:ModelBusy', 'Stop the current simulation before starting training.');
end
env = rlSimulinkEnv(modelName, modelName + "/RL Agent", obsInfo, actInfo, ...
    "UseFastRestart", fastRestart);
rng(baseSeed);

% 新 agent 才呼叫 factory；已有 checkpoint 時直接載入同一 agent。
if strlength(resumeAgentFile) == 0
if ~isempty(agentFactory)
    Agent_Stage2 = agentFactory(obsInfo,actInfo,trainingDevice);
else
%% Actor Network Architecture
% 未提供 modular factory 時的舊版 actor 建構分支。
inPath = [
        sequenceInputLayer(10, "Name", "observation")
        lstmLayer(128, "Name", "lstm_memory", ...
                  "OutputMode", "sequence", ...
                  "InputWeightsInitializer", "glorot", ...
                  "RecurrentWeightsInitializer", "orthogonal")
        fullyConnectedLayer(64, "Name", "ip_fc1");
        reluLayer("Name", "ip_relu1");
        fullyConnectedLayer(64, "Name", "ip_fc2");
        reluLayer("Name", "ip_relu2");
        fullyConnectedLayer(32, "Name", "ip_fc3");
        reluLayer("Name", "ip_relu3");
        fullyConnectedLayer(1, "Name", "ip_out");
];

meanPath = [
        fullyConnectedLayer(32, "Name", "mp_fc1");
        reluLayer("Name", "mp_relu1");
        fullyConnectedLayer(16, "Name", "mp_fc2");
        reluLayer("Name", "mp_relu2");
        fullyConnectedLayer(1, "Name", "mp_fc3");
        tanhLayer("Name", "tanh");
        scalingLayer("Name", "mp_out", "scale", actInfo.UpperLimit)
];

sdevPath = [
        fullyConnectedLayer(32, "Name", "vp_fc1");
        reluLayer("Name", "vp_relu1");
        fullyConnectedLayer(16, "Name", "vp_fc2");
        reluLayer("Name", "vp_relu2");
        fullyConnectedLayer(1, "Name", "vp_fc3");
        softplusLayer("Name", "sdev")
];

actnet = layerGraph(inPath);
actnet = addLayers(actnet, meanPath);
actnet = addLayers(actnet, sdevPath);
actnet = connectLayers(actnet, "ip_out", "mp_fc1/in");
actnet = connectLayers(actnet, "ip_out", "vp_fc1/in");

Actor = rlContinuousGaussianActor(actnet, obsInfo, actInfo, ...
    "ObservationInputNames", "observation", ...
    "ActionMeanOutputNames", "mp_out", ...
    "ActionStandardDeviationOutputNames", "sdev", ...
    "UseDevice", trainingDevice);

%% Critic Network Architecture
% 與 actor 分開的 value 網路，估計 PPO 所需狀態價值。
valnet = [
    sequenceInputLayer(10, "Name", "observation")
    lstmLayer(128, "Name", "lstm_value", ...
              "OutputMode", "sequence", ...
              "InputWeightsInitializer", "glorot", ...
              "RecurrentWeightsInitializer", "orthogonal")
    fullyConnectedLayer(64, "Name", "fc1");
    reluLayer("Name", "relu1");
    fullyConnectedLayer(32, "Name", "fc2");
    reluLayer("Name", "relu2");
    fullyConnectedLayer(16, "Name", "fc3");
    reluLayer("Name", "relu3");
    fullyConnectedLayer(1, "Name", "value")
];

Critic = rlValueFunction(valnet, obsInfo, "UseDevice", trainingDevice);

%% PPO Agent Configuration
% 組合 actor／critic 與 PPO 更新選項；續訓分支直接載入已保存 agent。
agentOpts = rlPPOAgentOptions(...
    "SampleTime", 0.1, ...
    "DiscountFactor", 0.98, ...
    "MiniBatchSize", 128, ...
    "ExperienceHorizon", 512, ...
    "NumEpoch", 3, ...
    "EntropyLossWeight", 0.01 ...
);

Agent_Stage2 = rlPPOAgent(Actor, Critic, agentOpts);

Agent_Stage2.AgentOptions.ActorOptimizerOptions.LearnRate = 5e-5;
Agent_Stage2.AgentOptions.ActorOptimizerOptions.GradientThreshold = 1;
Agent_Stage2.AgentOptions.CriticOptimizerOptions.LearnRate = 1e-4;
Agent_Stage2.AgentOptions.CriticOptimizerOptions.GradientThreshold = 3;
end

else
    fileInfo = whos('-file', char(resumeAgentFile));
    agentVariable = "";
    for candidate = ["saved_agent", "Agent_Stage2"]
        if any(strcmp({fileInfo.name}, candidate))
            agentVariable = candidate;
            break;
        end
    end
    if strlength(agentVariable) == 0
        error('Training:CheckpointFormat', 'Expected saved_agent or Agent_Stage2.');
    end
    % 只在記憶體內接續權重，隨後核對 observation／action／sample time。
    loadedAgent = load(char(resumeAgentFile), char(agentVariable));
    Agent_Stage2 = loadedAgent.(char(agentVariable));
    clear loadedAgent;
    if ~(isa(Agent_Stage2,'rl.agent.rlPPOAgent') || isa(Agent_Stage2,'rl.agent.rlSACAgent')) || ~isscalar(Agent_Stage2)
        error('Training:AgentType', 'Checkpoint must contain one supported PPO/SAC agent.');
    end
    savedObs = getObservationInfo(Agent_Stage2);
    savedAct = getActionInfo(Agent_Stage2);
    if ~isequal(savedObs.Dimension, obsInfo.Dimension) || ...
       ~isequal(savedAct.Dimension, actInfo.Dimension) || ...
       Agent_Stage2.AgentOptions.SampleTime ~= DT || ...
       ~isequal(savedAct.LowerLimit, actInfo.LowerLimit) || ...
       ~isequal(savedAct.UpperLimit, actInfo.UpperLimit)
        error('Training:AgentMismatch', 'Agent dimensions, limits or sample time do not match.');
    end
    fprintf('Loaded agent: %s\nContinuing with episode %d.\n', resumeAgentFile, resumeEpisode + 1);
end

%% Network Architecture Display
% Explicit new serial runs restore device through the serialized SAC state.
assert(any(executionMode==["serial","parallel"]),'Training:Mode','Invalid execution mode.');
if executionMode=="serial"
    assert(isa(Agent_Stage2,'rl.agent.rlSACAgent'),'Training:Mode','Serial mode currently supports SAC only.');
    Agent_Stage2=checkpoint_restore_sac_device(Agent_Stage2,trainingDevice);
end
% 只列印網路大小與 LSTM 單元，不做更新或評估。
if ~isempty(agentValidator), agentValidator(Agent_Stage2); end
fprintf('\n========== Network Architecture ==========\n');

actorNet = getModel(getActor(Agent_Stage2));
fprintf('Actor network layers: %d\n', numel(actorNet.Layers));
fprintf('Actor total parameters: %d\n', countParams(actorNet));

displayCritics = getCritic(Agent_Stage2);
criticNet = getModel(displayCritics(1));
fprintf('Number of critics: %d (architecture below is critic 1)\n',numel(displayCritics));
fprintf('Critic network layers: %d\n', numel(criticNet.Layers));
fprintf('Critic total parameters: %d\n', countParams(criticNet));

for i = 1:numel(actorNet.Layers)
    if contains(class(actorNet.Layers(i)), 'lstm', 'IgnoreCase', true)
        fprintf('Actor LSTM: %s, Hidden=%d\n', ...
            actorNet.Layers(i).Name, actorNet.Layers(i).NumHiddenUnits);
    end
end
for i = 1:numel(criticNet.Layers)
    if contains(class(criticNet.Layers(i)), 'lstm', 'IgnoreCase', true)
        fprintf('Critic LSTM: %s, Hidden=%d\n', ...
            criticNet.Layers(i).Name, criticNet.Layers(i).NumHiddenUnits);
    end
end

fprintf('===================================\n\n');

%% Trajectory Parameter Display
% 列印軌跡設定，供核對 window 點距／速度。
fprintf('\n========== Trajectory Parameter Settings ==========\n');
fprintf('Target speed (TARGET_SPEED): %.1f m/s\n', TARGET_SPEED);
fprintf('Sample time (DT): %.2f s\n', DT);
fprintf('Waypoint spacing (WAYPOINT_SPACING): %.2f m\n', WAYPOINT_SPACING);
fprintf('Actual moving window speed: %.1f m/s (= %.2f m / %.2f s)\n', ...
        WAYPOINT_SPACING/DT, WAYPOINT_SPACING, DT);
fprintf('===================================\n\n');

%% Centralized logging, matching the original DataQueue design
% worker 送事件給 client 寫 CSV，避免多個 worker 競爭同一檔案。
windLogFile = fullfile(runLogDir, 'wind_all.csv');
fid = fopen(windLogFile, 'w');
if fid == -1, error('Training:WindLog', 'Cannot create wind log.'); end
fprintf(fid, 'WorkerEpisode,Wind_E,Wind_N,Turb,Worker\n');
fclose(fid);
memoryLogFile = fullfile(runLogDir, 'memory_log.csv');
fid = fopen(memoryLogFile, 'w');
if fid == -1, error('Training:MemoryLog', 'Cannot create memory log.'); end
fprintf(fid, 'WorkerEpisode,Worker,Time,MATLABUsedBytes,AvailablePhysicalBytes\n');
fclose(fid);
dq = parallel.pool.DataQueue;
logListener = afterEach(dq, @(event) writeWorkerLog(event, windLogFile, memoryLogFile));
randomstart_stage2([], dq, true);
% 將此階段的 trajectory／wind 傳入每回合 ResetFcn，不重建 agent。
environmentConfig=[];
if ~isempty(curriculumContext), environmentConfig=curriculumContext.environment; end
env.ResetFcn = @(in) randomstart_stage2(in, dq, false, environmentConfig);

%% Local process pool (same six-worker intent as the original script)
% 先排除不相容且閒置的 pool；有其他工作時拒絕覆用或刪除。
pool = gcp('nocreate');
requestedWorkers = numWorkers;
if executionMode=="parallel"
if ~isempty(pool) && (~isa(pool, 'parallel.ProcessPool') || ...
        pool.NumWorkers < minWorkers || pool.NumWorkers > numWorkers || ...
        ~isa(pool.Cluster, 'parallel.cluster.Local'))
    % Do not discard unrelated running parfeval work.
    if ~isempty(pool.FevalQueue.RunningFutures) || ~isempty(pool.FevalQueue.QueuedFutures)
        error('Training:PoolBusy', 'Existing pool has active work; finish it before training.');
    end
    delete(pool);
    pool = [];
end
if isempty(pool)
    pool = checkpoint_open_pool(numWorkers, poolDiagnosticDir, minWorkers);
end
% WorkerRandomSeeds and all downstream options must match the actual pool.
% 成功取得 n 個就立即在本段使用 n 個；seed 數量及 options 同步採實際 n。
numWorkers = pool.NumWorkers;
% Workers share the local filesystem. Attach script for local helper callbacks.
addAttachedFiles(pool, {[mfilename('fullpath') '.m']});
updateAttachedFiles(pool);
else
    assert(isempty(pool),'Training:PoolBusy','Serial run requires a fresh process without a pool.');
    numWorkers=0;
    serialModelGuard=prepareTrainingModel(modelName,disableTrainingLogging,disableUAVAnimation);
end
workerConfig = struct('scriptDir', scriptDir, 'modelName', modelName, ...
    'environmentModelFile',environmentModelFile, ...
    'targetSpeed', TARGET_SPEED, 'dt', DT, 'spacing', WAYPOINT_SPACING, ...
    'disableLogging', disableTrainingLogging, ...
    'disableAnimation', disableUAVAnimation);
% Pool shutdown below releases worker processes instead of waiting for IdleTimeout.
%% Training
% 建立訓練 options 與每個實際 worker 的 seed，課程採段落回合數停止。
maxstep = ceil(300/DT);
stopCriteria="AverageReward";stopValue=targetReward;
if ~isempty(curriculumContext)
    stopEpisode=resumeEpisode+maxEpisodes;
    guardRules=[];
    guardFile=fullfile(saveDir,'training_guard.json');
    if isfile(guardFile),guardRules=jsondecode(fileread(guardFile));end
    stopCriteria="Custom";
    stopValue=@(stats) trainingcurriculum.progress_callback( ...
        stats,curriculumContext.stage,curriculumContext.state.stage_index, ...
        curriculumContext.stageCount,curriculumContext.state.start_episode,stopEpisode, ...
        checkpointEvery,guardRules);
end
% MaxEpisodes 以 resumeEpisode+新增回合設定；MaxStepsPerEpisode=300/DT，所以目前每回合上限 3000 步。
% EpisodeFrequency 表示按回合頻率保存；保存條件不等於成功條件，也不保證意外退出前未滿頻率的回合仍存在。
trainingOpts = rlTrainingOptions( ...
    "MaxEpisodes", resumeEpisode + maxEpisodes, ...
    "MaxStepsPerEpisode", maxstep, ...
    "StopTrainingCriteria", stopCriteria, ...
    "StopTrainingValue", stopValue, ...
    "ScoreAveragingWindowLength", averageWindow, ...
    "SaveAgentCriteria", "EpisodeFrequency", ...
    "SaveAgentValue", checkpointEvery, ...
    "SaveFileVersion", "-v7.3", ...
    "SaveAgentDirectory", checkpointDir, ...
    "SimulationStorageType", "none", ...
    "UseParallel", executionMode=="parallel", ...
    "Verbose", true, ...
    "Plots", trainingPlots ...
);
% sync 讓每輪並行訓練採同步模式；UseParallel 不保證要求的 worker 上限一定取得。
trainingOpts.ParallelizationOptions.Mode = "sync";
% 課程以本段 EpisodeCount 結束，不用跨階段平均 reward 提前通關。
if ~isempty(curriculumContext)
    % Callback may request normal return at a checkpoint boundary. Save first;
    % authoritative course/guard decisions remain below checkpoint_save_final.
    trainingOpts.Verbose=false;
end
% 1:numWorkers 產生 n 個連續偏移，與實際 pool 對齊；不同 attempt 的 baseSeed 會改變。
if executionMode=="parallel"
trainingOpts.ParallelizationOptions.WorkerRandomSeeds = baseSeed + (1:numWorkers);
end
trainingOpts.ParallelizationOptions.TransferBaseWorkspaceVariables = "on";
% Runtime queue callbacks are rebuilt each run, not stored in MAT checkpoints.
optionsForDisk = trainingOpts;
save(fullfile(runLogDir, 'TrainingOptions.mat'), 'optionsForDisk', 'numWorkers', 'requestedWorkers', 'minWorkers', ...
    'resumeAgentFile', 'fastRestart', '-v7.3');
if executionMode=="parallel"
    trainingOpts.ParallelizationOptions.SetupFcn = @() parallelWorkerState("setup", workerConfig, []);
    trainingOpts.ParallelizationOptions.CleanupFcn = @() parallelWorkerState("cleanup", workerConfig, []);
end
% Agent_Initial 是本段開始前的 agent，供檢查 resume 是否保留權重；不是這段訓練後成果。
save(fullfile(runLogDir, 'Agent_Initial.mat'), 'Agent_Stage2', '-v7.3');
copyfile([mfilename('fullpath') '.m'], fullfile(runLogDir, 'training_script_snapshot.m'));
clear training_stage2;
if executionMode=="serial",fprintf('Serial training ready: no worker pool; device=%s\n',trainingDevice);end
% Configure logging/animation on workers through SetupFcn/CleanupFcn.
% Keep the client model unchanged so parallel model transfer sees a saved model.
try
    trainInput = trainingOpts;
    % resumeHistory 帶已保存統計；替換其 TrainingOptions 只指定本段選項，不清空既有 episode 編號。
    if ~isempty(resumeHistory)
        resumeHistory.TrainingOptions = trainingOpts;
        trainInput = resumeHistory;
    end
    % 續訓將既有 history 與本段 options 一起交給 train，保留回合編號。
    training_stage2 = trainWithPoolCleanup(Agent_Stage2, env, trainInput, pool, closePoolOnExit);
catch trainingError
    % Best effort for MATLAB exceptions only, not process termination.
    try
        save(fullfile(runLogDir, 'Agent_OnError.mat'), 'Agent_Stage2', '-v7.3');
    catch saveError
        warning('Training:SaveFailed', '%s', saveError.message);
    end
    fid = fopen(fullfile(runLogDir, 'training_error.txt'), 'w');
    if fid ~= -1
        fprintf(fid, '%s', getReport(trainingError, 'extended', 'hyperlinks', 'off'));
        fclose(fid);
    end
    rethrow(trainingError);
end
% Avoid retaining live DataQueue callbacks in the results file.
training_stage2.TrainingOptions = optionsForDisk;
% 先完整保存 agent＋歷史，才用保存邊界的數據判定 guard／課程。
checkpoint_save_final(fullfile(saveDir,'Agent_Final.mat'),Agent_Stage2,training_stage2);
copyfile(fullfile(saveDir,'Agent_Final.mat'),fullfile(runLogDir,'Agent_Final.mat'));
save(fullfile(saveDir, 'TrainingResults.mat'), 'training_stage2', '-v7.3');
if isempty(curriculumContext)
    successSummary = checkpoint_mark_success(saveDir, training_stage2.EpisodeReward, ...
        targetReward, averageWindow);
else
    % guard 回傳 pause 時優先保留；只有空結果才執行課程過關判定。
    successSummary = trainingguard.check(saveDir,fullfile(saveDir,'Agent_Final.mat'));
    if isempty(successSummary)
        successSummary = trainingcurriculum.outcome(curriculumContext,training_stage2.EpisodeReward, ...
            training_stage2.EpisodeSteps,fullfile(saveDir,'Agent_Final.mat'));
    end
end
fprintf('Training stopped normally. Saved in:\n%s\n', saveDir);
%% Helper Functions
% 訓練、worker 環境、回合 reset 與路徑幾何輔助函式。
function result = trainWithPoolCleanup(agent, environment, options, pool, closeOnExit)
    guard = onCleanup(@() releaseTrainingPool(pool, closeOnExit)); %#ok<NASGU>
    result = train(agent, environment, options);
end

function releaseTrainingPool(pool, closeOnExit)
% 只在設定要求且 pool 有效時關閉它，不處理 supervisor 外的其他程序。
    if closeOnExit && ~isempty(pool) && isvalid(pool)
        delete(pool);
    end
end

function writeWorkerLog(event, windFile, memoryFile)
% 依 DataQueue 事件種類分流風場與記憶體 CSV，集中由 client 寫檔。
    % Only the client writes these shared files, as in the original script.
    if strcmp(event.kind, 'wind')
        appendWindRow(windFile, event.row);
    elseif strcmp(event.kind, 'memory')
        appendWindRow(memoryFile, event.row);
    end
end

function parallelWorkerState(action, config, dq)
% worker setup 保存／切換目錄、路徑與快取，cleanup 透過 guard 恢復模型及檔案環境。
    persistent modelGuard filesystemGuard
    global TARGET_SPEED DT WAYPOINT_SPACING pathFigure
    % Clear stale state when reusing a pool after an interrupted run.
    modelGuard = [];
    filesystemGuard = [];
    if action == "cleanup"
        randomstart_stage2([], dq, true);
        TARGET_SPEED = []; DT = []; WAYPOINT_SPACING = []; pathFigure = [];
        return;
    end
    TARGET_SPEED = config.targetSpeed;
    DT = config.dt;
    WAYPOINT_SPACING = config.spacing;
    pathFigure = []; % Never create worker-side figures.
    randomstart_stage2([], dq, true);
    previousFolder = pwd;
    previousPath = path;
    previousFileConfig = Simulink.fileGenControl('getConfig');
    filesystemGuard = onCleanup(@() restoreWorkerFilesystem( ...
        previousFolder, previousPath, previousFileConfig));
    try
        cd(config.scriptDir);
        % Avoid multiple workers writing the same slprj/cache files.
        cacheRoot = tempname;
        Simulink.fileGenControl('set', 'CacheFolder', fullfile(cacheRoot, 'cache'), ...
            'CodeGenFolder', fullfile(cacheRoot, 'codegen'), 'createDir', true);
        addpath(fileparts(config.environmentModelFile),'-begin');
        cd(fileparts(config.environmentModelFile));
        loadEnvironmentModel(config.environmentModelFile);
        modelGuard = prepareTrainingModel(config.modelName, ...
            config.disableLogging, config.disableAnimation);
    catch setupError
        modelGuard = [];
        filesystemGuard = [];
        rethrow(setupError);
    end
end

function loadEnvironmentModel(file)
% RL may preload the same model on workers. Refuse only a different file.
if bdIsLoaded('FAFA_Simulation')
    loaded=char(java.io.File(get_param('FAFA_Simulation','FileName')).getCanonicalPath());
    expected=char(java.io.File(char(file)).getCanonicalPath());
    assert(strcmpi(loaded,expected),'Environment:AlreadyLoaded','A different FAFA model is already loaded.');
end
load_system(file);
end

function restoreWorkerFilesystem(previousFolder, previousPath, previousFileConfig)
% 恢復 worker 原目錄、MATLAB path 與 Simulink 快取設定。
    Simulink.fileGenControl('setConfig', 'config', previousFileConfig);
    cd(previousFolder);
    path(previousPath);
end

function in = randomstart_stage2(in, dq, resetState, environmentConfig)
% 每回合抽樣整數風場、依課程選軌跡並寫入模型變數；resetState 清除持久狀態。
    % Path-generation helpers read the global trajectory settings.
    persistent lastwaypoints lastvelocity localEpisodeCounter
    if resetState
        lastwaypoints = [];
        lastvelocity = [];
        localEpisodeCounter = [];
        return;
    end

    % 沒有課程環境時才使用舊版 random／風場預設，保持非課程流程。
    legacyEnvironment=nargin<4 || isempty(environmentConfig);
    if legacyEnvironment
        environmentConfig=struct('trajectory',struct('type','random','refresh_every_worker_episodes',10), ...
            'wind',struct('east_mps',[-3 3],'north_mps',[-3 3],'turbulence',[0 2]));
    end
    if isempty(localEpisodeCounter)
        localEpisodeCounter = 0;
        if legacyEnvironment
            % Preserve the old random-number sequence for non-curriculum runs.
            [lastwaypoints,lastvelocity]=createPath_Stage2();
            displayPath(lastwaypoints,localEpisodeCounter);
        end
    end

    mdl = "FAFA_Simulation";

    pathUpdateFrequency = Inf;
    if strcmp(environmentConfig.trajectory.type,'random')
        pathUpdateFrequency=environmentConfig.trajectory.refresh_every_worker_episodes;
    end

    % Random wind disturbance, different for each episode.
    % 每回合抽樣 JSON 指定的整數風場；不代表 turbulence 內部噪音時序互相獨立。
    wind_E0 = randi(environmentConfig.wind.east_mps(:)',1,1);
    wind_N0 = randi(environmentConfig.wind.north_mps(:)',1,1);
    wind_turbulance_value0 = randi(environmentConfig.wind.turbulence(:)',1,1);

    try
        t = getCurrentTask(); wid = t.ID;
    catch
        wid = 0;
    end
    row = sprintf('%d,%.2f,%.2f,%d,%d', ...
        localEpisodeCounter + 1, wind_E0, wind_N0, wind_turbulance_value0, wid);
    send(dq, struct('kind', 'wind', 'row', row));

    % Log each worker separately; physical available RAM is system-wide.
    if ispc && mod(localEpisodeCounter, 100) == 0
        try
            [processMemory, systemMemory] = memory;
            memoryRow = sprintf('%d,%d,%s,%.0f,%.0f', localEpisodeCounter + 1, wid, ...
                char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
                processMemory.MemUsedMATLAB, systemMemory.PhysicalMemory.Available);
            send(dq, struct('kind', 'memory', 'row', memoryRow));
        catch memoryError
            warning('Training:MemoryLog', '%s', memoryError.message);
        end
    end
    in = setVariable(in, "wind_E0", wind_E0, "Workspace", mdl);
    in = setVariable(in, "wind_N0", wind_N0, "Workspace", mdl);
    in = setVariable(in, "wind_turbulance_value0", wind_turbulance_value0, "Workspace", mdl);

    % 固定／MAT 沿用路徑；random 依 worker-local 回合週期更新。
    if isempty(lastwaypoints) || (isfinite(pathUpdateFrequency) && mod(localEpisodeCounter, pathUpdateFrequency)==0)
        switch environmentConfig.trajectory.type
            case 'fixed_builtin'
                [lastwaypoints,lastvelocity]=createFixedPath();
            case 'mat'
                lastwaypoints=environmentConfig.trajectory.waypoints;
                lastvelocity=environmentConfig.trajectory.velocity;
            case 'random'
                [lastwaypoints,lastvelocity]=createPath_Stage2();
            otherwise
                error('Curriculum:Trajectory','Unknown trajectory type.');
        end
        fprintf('[Trajectory] Worker %d, local episode %d: new path (%d waypoints)\n', ...
                wid, localEpisodeCounter + 1, size(lastwaypoints, 1));
        displayPath(lastwaypoints, localEpisodeCounter + 1);
    end

    in = setVariable(in, "waypoints", lastwaypoints, "Workspace", mdl);
    in = setVariable(in, "velocity", lastvelocity, "Workspace", mdl);

    localEpisodeCounter = localEpisodeCounter + 1;
end

% Ranfdom path
function [waypoints, velocity] = createPath_Stage2()
% random 軌跡：交替抽樣直線段長與左右轉角，產生等高度路徑後依弧長重新等距取樣。
% 回傳 N×3 waypoints／velocity；使用呼叫者 RNG 與共用速度／點距，不自行設 seed 或訓練。
    global TARGET_SPEED DT WAYPOINT_SPACING

    if isempty(TARGET_SPEED)
        TARGET_SPEED = 15;
    end
    if isempty(DT), DT = 0.1; end
    if isempty(WAYPOINT_SPACING), WAYPOINT_SPACING = TARGET_SPEED * DT; end

    % 先按 DT 生成直線／轉彎步進，再重採樣成 WAYPOINT_SPACING 點距。
    numSteps = 4000;
    dt = DT;
    x0 = 50;
    y0 = 0;
    z0 = 70;
    angle = pi/2;
    speed = TARGET_SPEED;
    angularSpeedMax = pi/32;
    minSegmentLen = 150;
    maxSegmentLen = 500;
    turnCenterDeg = 60;
    turnRangeDeg = 20;
    turnCenterRad = deg2rad(turnCenterDeg);
    turnRangeRad = deg2rad(turnRangeDeg);

    waypoints = zeros(numSteps, 3);
    velocity = zeros(numSteps, 3);
    waypoints(1,:) = [x0, y0, z0];
    velocity(1,:) = [speed*sin(angle), speed*cos(angle), 0];

    currentStep = 1;

    while currentStep < numSteps
        % 隨機直線長度以時間步數抽樣，實際距離還取決於速度與 DT。
        thisSegmentSteps = randi([minSegmentLen, maxSegmentLen]);

        for k = 1:thisSegmentSteps
            currentStep = currentStep + 1;
            if currentStep > numSteps
                break;
            end

            x0 = x0 + speed*sin(angle)*dt;
            y0 = y0 + speed*cos(angle)*dt;

            waypoints(currentStep, :) = [x0, y0, z0];
            velocity(currentStep, :) = [speed*sin(angle), speed*cos(angle), 0];
        end

        if currentStep >= numSteps
            break;
        end

        if rand() < 0.5
            turnSignBase = 1;
        else
            turnSignBase = -1;
        end

        % 左右方向與轉角偏移分別抽樣；actual 更新使用 angularSpeedMax。
        turnOffset = (rand()*2 - 1) * turnRangeRad;
        targetAngle = angle + turnSignBase * (turnCenterRad + turnOffset);

        totalTurnAngle = abs(targetAngle - angle);
        angularSpeed = angularSpeedMax * (1 - 0.5 * (totalTurnAngle / pi));
        angularSpeed = max(angularSpeed, angularSpeedMax / 3);
        numTurnSteps = ceil(totalTurnAngle / (angularSpeedMax * dt));

        for t = 1:numTurnSteps
            currentStep = currentStep + 1;
            if currentStep > numSteps
                break;
            end

            turnDirection = sign(targetAngle - angle);
            angle = angle + turnDirection * angularSpeedMax * dt;

            x0 = x0 + speed*sin(angle)*dt;
            y0 = y0 + speed*cos(angle)*dt;

            waypoints(currentStep, :) = [x0, y0, z0];
            velocity(currentStep, :) = [speed*sin(angle), speed*cos(angle), 0];
        end

        for s = 1:size(waypoints, 1)
            if abs(waypoints(s, 1)) < 1e-3
                waypoints(s, 1) = 0;
            end
            if abs(waypoints(s, 2)) < 1e-3
                waypoints(s, 2) = 0;
            end
            if abs(velocity(s, 1)) < 1e-3
                velocity(s, 1) = 0;
            end
            if abs(velocity(s, 2)) < 1e-3
                velocity(s, 2) = 0;
            end
        end

        if currentStep < numSteps
            angle = targetAngle;
        end
    end

    x = waypoints(:,1);
    y = waypoints(:,2);
    z = waypoints(:,3);

    % 按累積弧長建立新取樣座標，位置／速度使用同一插值座標。
    d = [0; cumsum(sqrt(diff(x).^2 + diff(y).^2 + diff(z).^2))];
    d_new = (0:WAYPOINT_SPACING:d(end))';

    x_new = interp1(d, x, d_new, 'linear');
    y_new = interp1(d, y, d_new, 'linear');
    z_new = interp1(d, z, d_new, 'linear');

    waypoints = [x_new, y_new, z_new];

    velocity = zeros(size(waypoints));
    for i = 1:size(waypoints, 1)-1
        delta = waypoints(i+1, :) - waypoints(i, :);
        dist = norm(delta);
        if dist > 1e-6
            velocity(i, :) = speed * delta / dist;
        else
            velocity(i, :) = [0, speed, 0];
        end
    end
    velocity(end, :) = velocity(end-1, :);

    fprintf('[Random Path] Generated: %d waypoints, spacing %.2f m, total length %.1f m\n', ...
            size(waypoints, 1), WAYPOINT_SPACING, sum(vecnorm(diff(waypoints), 2, 2)));
end

% Display path
function displayPath(waypoints, episodeNum)
% 只有 showPathFigure 開啟時更新路徑視窗，僅用於觀察。
    global pathFigure

    if isempty(pathFigure) || ~isgraphics(pathFigure), return; end
    figure(pathFigure);
    clf;
    plot(waypoints(:,1), waypoints(:,2), 'b.-');
    axis equal;
    grid on;
    title(sprintf('Generated Path - Episode %d | Points: %d', ...
                  episodeNum, size(waypoints, 1)));
    xlabel('East (m)');
    ylabel('North (m)');

    hold on;
    plot(waypoints(1,1), waypoints(1,2), 'go', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
    plot(waypoints(end,1), waypoints(end,2), 'rs', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    legend('Path', 'Start', 'End', 'Location', 'best');
    hold off;

    drawnow;
end

function appendWindRow(fname, row)
% 將已格式化風場列附加至指定 CSV；無法開檔時警告，成功寫入後關檔。
    fid = fopen(fname, 'a');
    if fid ~= -1
        fprintf(fid, "%s\n", row);
        fclose(fid);
    else
        warning('Failed to write the wind log file: %s', fname);
    end
end

function cleanupGuard = prepareTrainingModel(mdl, disableLogging, disableAnimation)
% 先蒐集完整恢復計畫，再暫改 logging／動畫；onCleanup 不保存模型地恢復。
    % Build the complete restoration plan BEFORE mutating any model settings.
    targets = {char(mdl), 'FastRestart', 'off'};
    if disableLogging
        for parameter = {'SaveTime', 'SaveOutput', 'SaveState', 'SignalLogging'}
            targets(end+1,:) = {char(mdl), parameter{1}, 'off'}; %#ok<AGROW>
        end
        sinks = [find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                    'BlockType', 'ToWorkspace'); ...
                 find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                    'BlockType', 'Scope')];
        for k = 1:numel(sinks)
            targets(end+1,:) = {sinks{k}, 'Commented', 'on'}; %#ok<AGROW>
        end
    end
    if disableAnimation
        targets(end+1,:) = {[char(mdl) '/UAV Animation'], 'Commented', 'on'};
    end
    previous = targets;
    oldDirty = get_param(mdl, 'Dirty');
    for k = 1:size(targets,1)
        previous{k,3} = get_param(targets{k,1}, targets{k,2});
    end
    cleanupGuard = onCleanup(@() restoreModelSettings(mdl, previous, oldDirty)); %#ok<NASGU>
    for k = 1:size(targets,1)
        set_param(targets{k,1}, targets{k,2}, targets{k,3});
    end
end

function restoreModelSettings(mdl, previous, oldDirty)
% 逆序恢復參數，全部成功才還原 Dirty 標記；失敗以 warning 保留診斷。
    if ~bdIsLoaded(mdl), return; end
    restored = true;
    try
        set_param(mdl, 'FastRestart', 'off');
    catch err
        restored = false;
        warning('Training:RestoreFailed', '%s', err.message);
    end
    for j = size(previous,1):-1:1
        try
            set_param(previous{j,1}, previous{j,2}, previous{j,3});
        catch err
            restored = false;
            warning('Training:RestoreFailed', '%s: %s', previous{j,1}, err.message);
        end
    end
    if restored, set_param(mdl, 'Dirty', oldDirty); end
end
function n = countParams(net)
% 計算網路可學習參數元素數，供印出模型規模，不更改參數。
    n = 0;
    for i = 1:numel(net.Layers)
        layer = net.Layers(i);
        if isprop(layer, 'Weights') && ~isempty(layer.Weights)
            n = n + numel(layer.Weights);
        end
        if isprop(layer, 'Bias') && ~isempty(layer.Bias)
            n = n + numel(layer.Bias);
        end
        if isprop(layer, 'InputWeights') && ~isempty(layer.InputWeights)
            n = n + numel(layer.InputWeights);
        end
        if isprop(layer, 'RecurrentWeights') && ~isempty(layer.RecurrentWeights)
            n = n + numel(layer.RecurrentWeights);
        end
    end
end

% Fixed path
function [waypoints, velocity] = createFixedPath()
% 固定轉彎軌跡：依共用速度與點距，以直線及圓弧連接預定關鍵點。
% 回傳 N×3 waypoints／velocity；此函式與 engine 的 createFixedPath 內容須保持一致，評估器會逐字檢查。
    global TARGET_SPEED DT WAYPOINT_SPACING

    if isempty(TARGET_SPEED)
        TARGET_SPEED = 15;
    end
    if isempty(DT), DT = 0.1; end
    if isempty(WAYPOINT_SPACING), WAYPOINT_SPACING = TARGET_SPEED * DT; end

    speed = TARGET_SPEED;
    cruise_altitude = 70;
    waypoint_spacing = WAYPOINT_SPACING;
    turn_radius = 120;

    % 預定關鍵點決定固定任務；轉彎以有限半徑圓弧平滑連接。
    key_points = [
        50, 0;
        500, 0;
        500, -500;
        -1000, -500;
        -1000, 0;
        -50, 0;
        -50, 500;
        -1000, 500;
    ];

    segment_speeds = [
        speed;
        speed;
        speed;
        speed;
        speed;
        speed;
        speed];

    num_points = size(key_points, 1);
    num_segments = num_points - 1;

    all_waypoints = [];
    all_speeds = [];

    % 依直線段長與轉角計算切點；短段限制半徑，避免切點超出相鄰段。
    for seg = 1:num_segments
        p1 = key_points(seg, :);
        p2 = key_points(seg+1, :);

        seg_vec = p2 - p1;
        seg_len = norm(seg_vec);
        seg_dir = seg_vec / seg_len;

        if seg > 1
            prev_vec = key_points(seg, :) - key_points(seg-1, :);
            prev_dir = prev_vec / norm(prev_vec);

            dot_product = max(-1, min(1, dot(prev_dir, seg_dir)));
            turn_angle_rad = acos(dot_product);

            if turn_angle_rad > deg2rad(1)
                cross_z = prev_dir(1)*seg_dir(2) - prev_dir(2)*seg_dir(1);
                turn_direction = sign(cross_z);

                tangent_dist = turn_radius * tan(turn_angle_rad/2);
                prev_seg_len = norm(key_points(seg,:) - key_points(seg-1,:));
                max_tangent = min(seg_len, prev_seg_len) / 2;

                effective_radius = turn_radius;
                if tangent_dist > max_tangent * 0.99
                    tangent_dist = max_tangent * 0.99;
                    effective_radius = tangent_dist / tan(turn_angle_rad/2);
                end

                % 移除已累積路徑中被圓弧取代的尾端，避免轉彎重疊。
                if ~isempty(all_waypoints)
                    cut_length = tangent_dist;
                    distances_from_end = vecnorm(all_waypoints(end:-1:1, 1:2) - p1, 2, 2);
                    cut_idx = find(cumsum(diff([0; distances_from_end])) >= cut_length, 1);
                    if ~isempty(cut_idx) && cut_idx < size(all_waypoints, 1)
                        all_waypoints(end-cut_idx+1:end, :) = [];
                        all_speeds(end-cut_idx+1:end) = [];
                    end
                end

                arc_start = p1 - prev_dir * tangent_dist;
                arc_end = p1 + seg_dir * tangent_dist;

                perp_prev = [-prev_dir(2), prev_dir(1)] * turn_direction;
                circle_center = arc_start + perp_prev * effective_radius;

                start_angle = atan2(arc_start(2) - circle_center(2), arc_start(1) - circle_center(1));
                end_angle = atan2(arc_end(2) - circle_center(2), arc_end(1) - circle_center(1));

                if turn_direction > 0
                    if end_angle < start_angle, end_angle = end_angle + 2*pi; end
                else
                    if end_angle > start_angle, end_angle = end_angle - 2*pi; end
                end

                % 依點距取樣圓弧，保持與 window 速度設定相容的路徑密度。
                arc_length = abs(end_angle - start_angle) * effective_radius;
                num_arc_points = max(3, round(arc_length / waypoint_spacing));
                arc_angles = linspace(start_angle, end_angle, num_arc_points);

                arc_x = circle_center(1) + effective_radius * cos(arc_angles);
                arc_y = circle_center(2) + effective_radius * sin(arc_angles);
                arc_z = cruise_altitude * ones(size(arc_x));

                all_waypoints = [all_waypoints; arc_x(:), arc_y(:), arc_z(:)];
                all_speeds = [all_speeds; segment_speeds(seg) * ones(num_arc_points, 1)];

                p1 = [arc_x(end), arc_y(end)];
                seg_len = norm(p2 - p1);
            end
        end

        % 將剩餘直線等距離離散，跳過相鄰段重複的首點。
        if seg_len > waypoint_spacing
            num_straight_points = round(seg_len / waypoint_spacing);
            straight_x = linspace(p1(1), p2(1), num_straight_points)';
            straight_y = linspace(p1(2), p2(2), num_straight_points)';
            straight_z = cruise_altitude * ones(num_straight_points, 1);

            start_idx = 1;
            if ~isempty(all_waypoints), start_idx = 2; end

            new_pts = [straight_x(start_idx:end), straight_y(start_idx:end), straight_z(start_idx:end)];
            all_waypoints = [all_waypoints; new_pts];
            all_speeds = [all_speeds; segment_speeds(seg) * ones(size(new_pts,1), 1)];
        end
    end

    num_waypoints = size(all_waypoints, 1);
    velocity = zeros(num_waypoints, 3);

    % 速度方向採下一航點切線；末點沿用前一速度方向。
    for i = 1:num_waypoints
        if i < num_waypoints
            dir_vec = all_waypoints(i+1, :) - all_waypoints(i, :);
            d_norm = norm(dir_vec);
            if d_norm > 1e-6, dir_vec = dir_vec / d_norm; end
        else
            dir_vec = velocity(i-1, :) / max(norm(velocity(i-1, :)), 1e-6);
        end
        velocity(i, :) = all_speeds(i) * dir_vec;
    end

    waypoints = all_waypoints;

    fprintf('[Fixed Path] Generated: %d waypoints, spacing %.2f m, total length %.1f m\n', ...
            size(waypoints, 1), waypoint_spacing, sum(vecnorm(diff(waypoints), 2, 2)));
end
