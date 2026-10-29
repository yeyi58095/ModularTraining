function passed=frozen_gate(context,agentFile)
% Require a complete immutable-source evaluation of this exact checkpoint.
% Read-only: no training, no evaluation launch, no guard unlock.
passed=false;
if ~isfile(agentFile),return;end
root=fileparts(fileparts(mfilename('fullpath')));
g=context.stage.frozen_gate;
plan=trainingcurriculum.load_plan(fullfile(context.sessionDir,'curriculum.json'),false);
requiredStages=unique([1 context.state.stage_index]);
[env,~]=trainingenv.resolve(context.sessionDir);
expected=struct('agent',checkpointreview.sha256(agentFile), ...
    'curriculum',checkpointreview.sha256(fullfile(context.sessionDir,'curriculum.json')), ...
    'environment',checkpointreview.sha256(env), ...
    'runtime',checkpointreview.sha256(fullfile(root,'runtime','training_engine.m')), ...
    'generator',checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')));
files=dir(fullfile(context.sessionDir,'reports','evaluation_*','evaluation.json'));
for k=1:numel(files)
    try
        r=jsondecode(fileread(fullfile(files(k).folder,files(k).name)));
        if ~strcmp(r.status,'complete') || ~r.weights_unchanged || r.use_exploration || ...
                r.max_steps~=3000 || ~r.route_metrics_enabled || ~strcmp(r.guidance_variant,'baseline') || ...
                ~strcmp(r.random_path_sha256,expected.generator) || ...
                ~strcmp(r.curriculum_sha256,expected.curriculum) || ...
                ~strcmp(r.model_sha256,expected.environment) || ~strcmp(r.runtime_sha256,expected.runtime)
            continue;
        end
        checkpoints=r.checkpoints;if iscell(checkpoints),checkpoints=[checkpoints{:}];end
        match=checkpoints(strcmp({checkpoints.sha256},expected.agent));
        if numel(match)~=1,continue;end
        rows=r.results;if iscell(rows),rows=[rows{:}];end
        ok=true;
        for stage=requiredStages
            for seed=g.seeds(:)'
                ix=[rows.checkpoint_episode]==match.episode & [rows.seed]==seed & ...
                    strcmp({rows.stage_id},plan.stages{stage}.id);
                if nnz(ix)~=1,ok=false;continue;end
                row=rows(ix);m=row.route_metrics.after_10_seconds;
                ok=ok && row.steps==3000 && m.count>0 && ...
                    isfinite(m.max_m) && isfinite(m.rms_m) && ...
                    m.max_m<=g.max_distance_m && m.rms_m<=g.max_rms_m;
            end
        end
        if ok,passed=true;return;end
    catch
        % Partial/older reports cannot grant advancement.
    end
end
end
