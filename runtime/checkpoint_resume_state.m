function [history, episode, runDir] = checkpoint_resume_state(agentFile)
% 續訓歷史讀取：從 MAT 內容取得 history、實際 episode 與所屬 runDir。
% 相容已保存歷史格式，必要時在記憶體壓縮 SimulationInfo；從不以檔名推算進度或覆寫 checkpoint。
% Read real training history. Never infer completed episodes from a filename.
    agentFile = char(agentFile);
    runDir = fileparts(agentFile);
    [parent,leaf] = fileparts(runDir);
    if strcmp(leaf,'checkpoints'), runDir = parent; end
    entries = whos('-file',agentFile);
    names = string({entries.name});
    if any(names == "savedAgentResult")
        data = load(agentFile,'savedAgentResult'); history = data.savedAgentResult;
    elseif any(names == "training_stage2")
        data = load(agentFile,'training_stage2'); history = data.training_stage2;
    else
        % Legacy Final files stored history separately. Only accept that exact name.
        [~,stem] = fileparts(agentFile);
        resultFile = fullfile(runDir,'TrainingResults.mat');
        if strcmp(stem,'Agent_Final') && isfile(resultFile)
            data = load(resultFile,'training_stage2'); history = data.training_stage2;
        else
            error('Checkpoint:MissingHistory', ...
                'Checkpoint has no training history. Use a regular AgentN.mat checkpoint; filename alone cannot establish progress.');
        end
    end
    supported = isa(history,'rl.train.result.rlTrainingResult') || isa(history,'rl.train.rlTrainingResult');
    if ~supported || ~isscalar(history) || isempty(history.EpisodeIndex)
        error('Checkpoint:InvalidHistory','Expected a nonempty R2024b rlTrainingResult.');
    end
    episode = double(history.EpisodeIndex(end));
    if ~isfinite(episode) || episode < 1 || fix(episode) ~= episode || numel(history.EpisodeReward) ~= episode
        error('Checkpoint:InvalidHistory','Training history has inconsistent episode numbering.');
    end
    % Retain scalar training statistics, not old per-episode simulation outputs.
    if ~isempty(history.SimulationInfo)
        if isa(history,'rl.train.result.rlTrainingResult')
            % R2024b stores SimulationInfo behind a read-only property. Rebuild
            % the result from scalar statistics using its version-specific factory.
            fields = {'TimeStamp','EpisodeIndex','EpisodeReward','EpisodeSteps', ...
                'EpisodeQ0','EvaluationStatistic','ActorGradientSteps','CriticGradientSteps'};
            compact = struct('SimulationInfoStorage',[]);
            for k = 1:numel(fields), compact.(fields{k}) = history.(fields{k}); end
            history = rl.train.result.rlTrainingResult.fromResultStruct(compact,history.Information);
        else
            history = setSimulationInfo(history, []);
        end
    end
end
