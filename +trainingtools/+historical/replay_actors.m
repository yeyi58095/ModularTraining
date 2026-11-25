function outputDir = replay_actors(dataset)
% Compare frozen actors on the same recorded observations for a historical study.
arguments
    dataset (1,1) string {mustBeMember(dataset,["lab","recovery","regression"])}
end
[dataRoot, outputDir] = diagnostic_paths(char("replay_actors_" + dataset));
switch dataset
    case "lab"
        bundle = fullfile(dataRoot,'lab_recovery_e44b46f8');
        traces = fullfile(bundle,'reports','evaluation_20261010_183235_tp0d559eeb');
        episodes = [10600 10700];
        seed = 101;
    case "recovery"
        bundle = fullfile(dataRoot,'recovery_review_20261016');
        traces = fullfile(bundle,'reports','evaluation_20261016_192536_tpcebd1553');
        episodes = [18000 18100 18200 18300];
        seed = 501;
    case "regression"
        bundle = fullfile(dataRoot,'regression_models_20261016');
        traces = fullfile(dataRoot,'regression_20261016','evaluation_20261016_160454_tp76e91eb6');
        episodes = [18400 18500 18600];
        seed = 501;
end
rows = {};
for traceEpisode = episodes
    traceName = sprintf('ep%d_stage1_seed%d.mat',traceEpisode,seed);
    trace = load(fullfile(traces,traceName),'experience');
    experience = trace.experience;
    names = fieldnames(experience.Observation);
    observations = reshape(experience.Observation.(names{1}).Data,10,[]);
    names = fieldnames(experience.Action);
    actions = double(experience.Action.(names{1}).Data(:));
    count = min(150,numel(actions));
    for episode = episodes
        checkpoint = fullfile(bundle,'checkpoints',sprintf('Agent%d.mat',episode));
        variables = whos('-file',checkpoint);
        name = 'saved_agent';
        if ~any(strcmp({variables.name},name))
            name = 'Agent_Stage2';
        end
        saved = load(checkpoint,name);
        actor = getActor(saved.(name));
        actor.UseDevice = 'cpu';
        before = getLearnableParameters(actor);
        actor.State = cellfun(@(state) state .* 0,actor.State,'UniformOutput',false);
        means = zeros(count,1);
        sigmas = zeros(count,1);
        for t = 1:count
            [distribution,next] = evaluate(actor,{observations(:,t)});
            actor.State = cellfun(@dlarray,next,'UniformOutput',false);
            means(t) = double(distribution{1});
            sigmas(t) = double(distribution{2});
        end
        assert(isequaln(before,getLearnableParameters(actor)));
        row = struct('trace_episode',traceEpisode,'actor_episode',episode, ...
            'means',means,'stds',sigmas,'recorded_actions',actions(1:count), ...
            'own_trace_max_error',[]);
        if episode == traceEpisode
            row.own_trace_max_error = max(abs(means-actions(1:count)));
        end
        rows{end+1} = row; %#ok<AGROW>
        fprintf('trace=%d actor=%d own_error=%s\n',traceEpisode,episode,mat2str(row.own_trace_max_error));
    end
end
trainingcurriculum.write_json(fullfile(outputDir,'actor_replay.json'),rows);
end
