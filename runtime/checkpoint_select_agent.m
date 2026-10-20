function resumeFile = checkpoint_select_agent(candidates)
% checkpoint 選擇：按 supervisor 提供的候選順序，檢查可讀 agent、介面與真實保存歷史。
% 回傳第一個相容檔；所有既有候選都不可用時拒絕從頭訓練，不改候選檔案。
% Select the newest readable compatible candidate, preserving fallback order.
    candidates = string(candidates);
    resumeFile = "";
    for k = 1:numel(candidates)
        try
            entries = whos('-file',candidates(k));
            names = string({entries.name});
            name = "saved_agent";
            if ~any(names == name), name = "Agent_Stage2"; end
            if ~any(names == name), error('Checkpoint:Format','Missing agent.'); end
            data = load(candidates(k),name);
            agent = data.(name);
            if ~(isa(agent,'rl.agent.rlPPOAgent') || isa(agent,'rl.agent.rlSACAgent')) || ~isscalar(agent)
                error('Checkpoint:Format','Not a single supported PPO/SAC agent.');
            end
            obs = getObservationInfo(agent); act = getActionInfo(agent);
            if ~isequal(obs.Dimension,[10 1]) || ~isequal(act.Dimension,[1 1]) || ...
                    agent.AgentOptions.SampleTime ~= 0.1 || ...
                    ~isequal(act.LowerLimit,-1) || ~isequal(act.UpperLimit,1)
                error('Checkpoint:Incompatible','Agent does not match this model.');
            end
            checkpoint_resume_state(candidates(k)); % Must also have compatible real progress.
            resumeFile = candidates(k);
            clear agent data;
            break;
        catch err
            fprintf('Skipping unusable checkpoint %s: %s\n',candidates(k),err.message);
        end
    end
    if ~isempty(candidates) && strlength(resumeFile) == 0
        error('Checkpoint:NoValidCheckpoint','No readable compatible checkpoint; refusing to start from scratch.');
    end
end
