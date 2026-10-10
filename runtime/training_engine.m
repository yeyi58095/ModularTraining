%% LSTM-PPO parallel training with periodic checkpoints (R2024b)
% Run the WHOLE script in a fresh MATLAB session.
% Native crashes cannot be caught; periodic checkpoints protect completed work.
% Resume preserves training statistics/episode numbers in the same experiment folder.
clc;
warning('on', 'all');

%% User settings
resumeAgentFile = ""; % Full path to Agent100.mat or Agent_Final.mat; "" = new
numWorkers = 6; % Original script's intended local pool size
minWorkers = 1;
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
% Entrypoint/automatic supervisor supplies only these known settings.
if exist('checkpointOverrides', 'var') && isstruct(checkpointOverrides)
    allowed = {'resumeAgentFile','numWorkers','minWorkers','checkpointEvery','maxEpisodes', ...
        'trainingDevice','fastRestart','targetReward','averageWindow', ...
        'trainingPlots','baseSeed','closePoolOnExit','outputRoot','poolDiagnosticDir', ...
        'agentFactory','agentValidator','curriculumContext'};
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
global episodeCounter pathFigure wind_setup TARGET_SPEED DT WAYPOINT_SPACING
episodeCounter = 0;
wind_setup = [];
pathFigure = [];
if showPathFigure
    pathFigure = figure('Name', 'Path Display', 'NumberTitle', 'off');
end

%% Global Trajectory Parameters
% Keep the moving window speed consistent with the target speed:
% WAYPOINT_SPACING = TARGET_SPEED * DT
TARGET_SPEED = 15;      % Target speed (m/s)
DT = 0.1;               % Sample time (s)
WAYPOINT_SPACING = TARGET_SPEED * DT;

%% Observation and Action Space Definition
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
modelName = "FAFA_Simulation";

% Do not save changes to the original model.
load_system(fullfile(scriptDir, modelName + ".slx"));
if ~strcmp(get_param(modelName, 'SimulationStatus'), 'stopped')
    error('Training:ModelBusy', 'Stop the current simulation before starting training.');
end
env = rlSimulinkEnv(modelName, modelName + "/RL Agent", obsInfo, actInfo, ...
    "UseFastRestart", fastRestart);
rng(baseSeed);

if strlength(resumeAgentFile) == 0
if ~isempty(agentFactory)
    Agent_Stage2 = agentFactory(obsInfo,actInfo,trainingDevice);
else
%% Actor Network Architecture
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
    loadedAgent = load(char(resumeAgentFile), char(agentVariable));
    Agent_Stage2 = loadedAgent.(char(agentVariable));
    clear loadedAgent;
    if ~isa(Agent_Stage2, 'rl.agent.rlPPOAgent') || ~isscalar(Agent_Stage2)
        error('Training:AgentType', 'Checkpoint must contain one PPO agent.');
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
if ~isempty(agentValidator), agentValidator(Agent_Stage2); end
fprintf('\n========== Network Architecture ==========\n');

actorNet = getModel(getActor(Agent_Stage2));
fprintf('Actor network layers: %d\n', numel(actorNet.Layers));
fprintf('Actor total parameters: %d\n', countParams(actorNet));

criticNet = getModel(getCritic(Agent_Stage2));
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
fprintf('\n========== Trajectory Parameter Settings ==========\n');
fprintf('Target speed (TARGET_SPEED): %.1f m/s\n', TARGET_SPEED);
fprintf('Sample time (DT): %.2f s\n', DT);
fprintf('Waypoint spacing (WAYPOINT_SPACING): %.2f m\n', WAYPOINT_SPACING);
fprintf('Actual moving window speed: %.1f m/s (= %.2f m / %.2f s)\n', ...
        WAYPOINT_SPACING/DT, WAYPOINT_SPACING, DT);
fprintf('===================================\n\n');

%% Centralized logging, matching the original DataQueue design
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
environmentConfig=[];
if ~isempty(curriculumContext), environmentConfig=curriculumContext.environment; end
env.ResetFcn = @(in) randomstart_stage2(in, dq, false, environmentConfig);

%% Local process pool (same six-worker intent as the original script)
pool = gcp('nocreate');
requestedWorkers = numWorkers;
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
numWorkers = pool.NumWorkers;
% Workers share the local filesystem. Attach script for local helper callbacks.
addAttachedFiles(pool, {[mfilename('fullpath') '.m']});
updateAttachedFiles(pool);
workerConfig = struct('scriptDir', scriptDir, 'modelName', modelName, ...
    'targetSpeed', TARGET_SPEED, 'dt', DT, 'spacing', WAYPOINT_SPACING, ...
    'disableLogging', disableTrainingLogging, ...
    'disableAnimation', disableUAVAnimation);
% Pool shutdown below releases worker processes instead of waiting for IdleTimeout.
%% Training
maxstep = ceil(300/DT);
trainingOpts = rlTrainingOptions( ...
    "MaxEpisodes", resumeEpisode + maxEpisodes, ...
    "MaxStepsPerEpisode", maxstep, ...
    "StopTrainingCriteria", "AverageReward", ...
    "StopTrainingValue", targetReward, ...
    "ScoreAveragingWindowLength", averageWindow, ...
    "SaveAgentCriteria", "EpisodeFrequency", ...
    "SaveAgentValue", checkpointEvery, ...
    "SaveFileVersion", "-v7.3", ...
    "SaveAgentDirectory", checkpointDir, ...
    "SimulationStorageType", "none", ...
    "UseParallel", true, ...
    "Verbose", true, ...
    "Plots", trainingPlots ...
);
trainingOpts.ParallelizationOptions.Mode = "sync";
if ~isempty(curriculumContext)
    % Stage decisions are made only after the segment is saved. Do not let
    % whole-experiment reward history trigger the legacy global success rule.
    trainingOpts.StopTrainingCriteria = "EpisodeCount";
    trainingOpts.StopTrainingValue = resumeEpisode + maxEpisodes;
end
trainingOpts.ParallelizationOptions.WorkerRandomSeeds = baseSeed + (1:numWorkers);
trainingOpts.ParallelizationOptions.TransferBaseWorkspaceVariables = "on";
% Runtime queue callbacks are rebuilt each run, not stored in MAT checkpoints.
optionsForDisk = trainingOpts;
save(fullfile(runLogDir, 'TrainingOptions.mat'), 'optionsForDisk', 'numWorkers', 'requestedWorkers', 'minWorkers', ...
    'resumeAgentFile', 'fastRestart', '-v7.3');
trainingOpts.ParallelizationOptions.SetupFcn = @() parallelWorkerState("setup", workerConfig, []);
trainingOpts.ParallelizationOptions.CleanupFcn = @() parallelWorkerState("cleanup", workerConfig, []);
save(fullfile(runLogDir, 'Agent_Initial.mat'), 'Agent_Stage2', '-v7.3');
copyfile([mfilename('fullpath') '.m'], fullfile(runLogDir, 'training_script_snapshot.m'));
clear training_stage2;
% Configure logging/animation on workers through SetupFcn/CleanupFcn.
% Keep the client model unchanged so parallel model transfer sees a saved model.
try
    trainInput = trainingOpts;
    if ~isempty(resumeHistory)
        resumeHistory.TrainingOptions = trainingOpts;
        trainInput = resumeHistory;
    end
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
checkpoint_save_final(fullfile(saveDir,'Agent_Final.mat'),Agent_Stage2,training_stage2);
copyfile(fullfile(saveDir,'Agent_Final.mat'),fullfile(runLogDir,'Agent_Final.mat'));
save(fullfile(saveDir, 'TrainingResults.mat'), 'training_stage2', '-v7.3');
if isempty(curriculumContext)
    successSummary = checkpoint_mark_success(saveDir, training_stage2.EpisodeReward, ...
        targetReward, averageWindow);
else
    successSummary = trainingguard.check(saveDir,fullfile(saveDir,'Agent_Final.mat'));
    if isempty(successSummary)
        successSummary = trainingcurriculum.outcome(curriculumContext,training_stage2.EpisodeReward, ...
            training_stage2.EpisodeSteps,fullfile(saveDir,'Agent_Final.mat'));
    end
end
fprintf('Training stopped normally. Saved in:\n%s\n', saveDir);
%% Helper Functions
function result = trainWithPoolCleanup(agent, environment, options, pool, closeOnExit)
    guard = onCleanup(@() releaseTrainingPool(pool, closeOnExit)); %#ok<NASGU>
    result = train(agent, environment, options);
end

function releaseTrainingPool(pool, closeOnExit)
    if closeOnExit && ~isempty(pool) && isvalid(pool)
        delete(pool);
    end
end

function writeWorkerLog(event, windFile, memoryFile)
    % Only the client writes these shared files, as in the original script.
    if strcmp(event.kind, 'wind')
        appendWindRow(windFile, event.row);
    elseif strcmp(event.kind, 'memory')
        appendWindRow(memoryFile, event.row);
    end
end

function parallelWorkerState(action, config, dq)
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
        load_system(fullfile(config.scriptDir, config.modelName + ".slx"));
        modelGuard = prepareTrainingModel(config.modelName, ...
            config.disableLogging, config.disableAnimation);
    catch setupError
        modelGuard = [];
        filesystemGuard = [];
        rethrow(setupError);
    end
end

function restoreWorkerFilesystem(previousFolder, previousPath, previousFileConfig)
    Simulink.fileGenControl('setConfig', 'config', previousFileConfig);
    cd(previousFolder);
    path(previousPath);
end

function in = randomstart_stage2(in, dq, resetState, environmentConfig)
    % Path-generation helpers read the global trajectory settings.
    persistent lastwaypoints lastvelocity localEpisodeCounter
    if resetState
        lastwaypoints = [];
        lastvelocity = [];
        localEpisodeCounter = [];
        return;
    end

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
    global TARGET_SPEED DT WAYPOINT_SPACING

    if isempty(TARGET_SPEED)
        TARGET_SPEED = 15;
    end
    if isempty(DT), DT = 0.1; end
    if isempty(WAYPOINT_SPACING), WAYPOINT_SPACING = TARGET_SPEED * DT; end

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
    fid = fopen(fname, 'a');
    if fid ~= -1
        fprintf(fid, "%s\n", row);
        fclose(fid);
    else
        warning('Failed to write the wind log file: %s', fname);
    end
end

function cleanupGuard = prepareTrainingModel(mdl, disableLogging, disableAnimation)
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
