function resumeFile = checkpoint_select_agent(candidates)
% Select the newest readable compatible candidate, preserving fallback order.
    candidates = string(candidates);
    resumeFile = "";
    for k = 1:numel(candidates)
        try
            entries = whos('-file',candidates(k));
            names = string({entries.name});
            name = "saved_agent";
            if ~any(names == name), name = "Agent_Stage2"; end
            if ~any(names == name), error('Checkpoint:Format','Missing PPO agent.'); end
            data = load(candidates(k),name);
            agent = data.(name);
            if ~isa(agent,'rl.agent.rlPPOAgent') || ~isscalar(agent)
                error('Checkpoint:Format','Not a single PPO agent.');
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
