function checkpoint_attempt(configFile)
% One fresh MATLAB process. Supervisor handles native process crashes.
    cfg = jsondecode(fileread(configFile));
    addpath(cfg.scriptDir);
    resumeFile = checkpoint_select_agent(cfg.resumeCandidates);
    checkpointOverrides = struct('numWorkers',cfg.numWorkers, ...
        'checkpointEvery',cfg.checkpointEvery,'maxEpisodes',cfg.episodesPerProcess, ...
        'targetReward',cfg.targetReward,'averageWindow',cfg.averageWindow, ...
        'resumeAgentFile',resumeFile,'trainingDevice',string(cfg.trainingDevice), ...
        'outputRoot',cfg.sessionDir,'baseSeed',cfg.attempt*10000, ...
        'trainingPlots',"none",'closePoolOnExit',true, ...
        'poolDiagnosticDir',cfg.attemptDir);
    if isfield(cfg,'modularRoot')
        addpath(cfg.modularRoot);
        checkpointOverrides = training(cfg,checkpointOverrides);
    end
    % Run in the base workspace: the model resolves Agent_Stage2 there.
    assignin('base','checkpointOverrides',checkpointOverrides);
    script = fullfile(cfg.scriptDir,'training_engine.m');
    evalin('base',sprintf('run(''%s'');',strrep(script,'''','''''')));
    outcome = evalin('base','successSummary');
    outcome.resumeFile = char(resumeFile);
    fid = fopen(fullfile(cfg.attemptDir,'result.json'),'w','n','UTF-8');
    assert(fid ~= -1,'Cannot write attempt result.');
    fprintf(fid,'%s',jsonencode(outcome));
    fclose(fid);
    fprintf('Attempt finished: episodes=%d, trailing mean=%.4f, success=%d\n', ...
        outcome.episodes,outcome.averageReward,outcome.success);
end
