function checkpoint_attempt(configFile)
% 單次 attempt 入口：新 MATLAB 程序讀取 attempt.json，選定 checkpoint 並組合 overrides。
% 課程／guard 可提前回傳 terminal；否則在 base workspace 執行 engine，最終將 outcome 寫入 result.json。
% One fresh MATLAB process. Supervisor handles native process crashes.
    cfg = jsondecode(fileread(configFile));
    if ~isfield(cfg,'minWorkers'), cfg.minWorkers = 1; end
    addpath(cfg.scriptDir);
    % 先選可讀且相容 checkpoint，並將實際來源傳給 engine。
    resumeFile = checkpoint_select_agent(cfg.resumeCandidates);
    % struct 的名稱／值配對建立設定；cfg.attempt*10000 是本 attempt seed 基準，並非跨所有實驗固定 seed。
    checkpointOverrides = struct('numWorkers',cfg.numWorkers,'minWorkers',cfg.minWorkers, ...
        'checkpointEvery',cfg.checkpointEvery,'maxEpisodes',cfg.episodesPerProcess, ...
        'targetReward',cfg.targetReward,'averageWindow',cfg.averageWindow, ...
        'resumeAgentFile',resumeFile,'trainingDevice',string(cfg.trainingDevice), ...
        'outputRoot',cfg.sessionDir,'baseSeed',cfg.attempt*10000, ...
        'trainingPlots',"none",'closePoolOnExit',true, ...
        'poolDiagnosticDir',cfg.attemptDir);
    outcome=[];
    if isfield(cfg,'modularRoot')
        addpath(cfg.modularRoot);
        checkpointOverrides = training(cfg,checkpointOverrides);
        if (isfield(cfg,'curriculumEnabled') && cfg.curriculumEnabled) || isfile(fullfile(cfg.sessionDir,'curriculum.json'))
            % guard 優先；已暫停或達預算的 run 可在 engine 執行前直接返回。
            outcome=trainingguard.check(cfg.sessionDir,resumeFile);
            % 沒有 terminal 才進 engine；提前 pause／complete 仍會寫 result.json。
            if isempty(outcome)
                % 階段只依據已保存歷史，段落回合上限裁到當階段剩餘預算。
                [context,outcome]=trainingcurriculum.prepare(cfg.sessionDir,resumeFile);
                checkpointOverrides.curriculumContext=context;
                checkpointOverrides.maxEpisodes=min(cfg.episodesPerProcess,context.remainingEpisodes);
                guardFile=fullfile(cfg.sessionDir,'training_guard.json');
                if isfile(guardFile)
                    rules=jsondecode(fileread(guardFile));
                    remaining=rules.origin_episode+rules.max_additional_episodes-context.resumeEpisode;
                    checkpointOverrides.maxEpisodes=min(checkpointOverrides.maxEpisodes,remaining);
                end
            end
        end
    end
    if isempty(outcome)
        % Run in the base workspace: the model resolves Agent_Stage2 there.
        % base workspace 是 Simulink 查找 Agent_Stage2 的位置；assignin 寫變數，evalin 在該工作區執行腳本。
        assignin('base','checkpointOverrides',checkpointOverrides);
        script = fullfile(cfg.scriptDir,'training_engine.m');
        evalin('base',sprintf('run(''%s'');',strrep(script,'''','''''')));
        outcome = evalin('base','successSummary');
    end
    % 記錄本次實際 checkpoint 來源，供 supervisor 與事後稽核。
    outcome.resumeFile = char(resumeFile);
    fid = fopen(fullfile(cfg.attemptDir,'result.json'),'w','n','UTF-8');
    assert(fid ~= -1,'Cannot write attempt result.');
    fprintf(fid,'%s',jsonencode(outcome));
    fclose(fid);
    fprintf('Attempt finished: episodes=%d, trailing mean=%.4f, success=%d\n', ...
        outcome.episodes,outcome.averageReward,outcome.success);
end
