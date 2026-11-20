function bundle=run_sac_update_frequency(mode)
% Prepare, or explicitly run, one paired 50-episode SAC learning-frequency trial.
arguments
    mode (1,1) string {mustBeMember(mode,["prepare","run"])} = "prepare"
end
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; restore=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'),'-begin');
bundle=fullfile(root,'artifacts','packages','sac-update-frequency-20261121');
if ~isfolder(bundle),mkdir(bundle);end
lock=lockFile(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledger=fullfile(bundle,'review.json');
if isfile(ledger)
    state=read(ledger);
    if any(strcmp(state.status,{'complete','cancelled'}))
        fprintf('Trial already ended. Use PackageOnly to collect evidence.\n');return
    end
    assert(strcmp(state.status,'prepared'),'UpdateFrequency:Interrupted', ...
        'Prior preparation or training may be incomplete. Inspect the saved ledger without relaunching.');
end

source=fullfile(root,'experiments','sac_random_route_v1','runs','20261119_004245_recovery_tpf24d3776');
source=trainingtools.local_data_path(root,source);
parent=fullfile(source,'Agent_Final.mat');
sourceHash='a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6';
origin=1700; limit=50; capacity=500000; sourceLength=337132;
trainingSeed=20261127;
freshSeeds=[2000012301 2000012302 2000012304:2000012311];
diagnosticSeed=2000012105;
seeds=[freshSeeds diagnosticSeed];
weakWind=[1 0;-1 1;0 1;-1 -1;-1 1;0 -1;1 1;-1 0;-1 -1;1 -1;1 1];
weakWind(:,3)=0;
labels={'frequency1','frequency2'};
sourceStatus=read(fullfile(source,'status.json'));
sourceOutcome=read(fullfile(source,'curriculum_outcome.json'));
sourceStage=read(fullfile(source,'curriculum_state.json'));
sourceModel=read(fullfile(source,'model.json'));
sourceControl=read(fullfile(source,'control.json'));
assert(strcmp(version('-release'),'2024b') && strcmp(sourceStatus.state,'paused') && ...
    sourceStage.stage_index==2 && sourceStage.start_episode==1000 && ...
    sourceOutcome.episodes==origin && strcmp(sourceOutcome.curriculumReason,'recovery_budget') && ...
    strcmp(sourceModel.name,'sac_paper64') && sourceModel.learningFrequency==1 && ...
    sourceModel.actorLearnRate==1.5e-4 && sourceModel.criticLearnRate==3e-4 && ...
    sourceModel.experienceBufferLength==capacity && strcmp(sourceControl.executionMode,'parallel') && ...
    strcmp(sourceControl.trainingDevice,'gpu') && sourceControl.numWorkers==6 && ...
    sourceControl.minWorkers==6 && isempty(sourceControl.fallbackWorkers) && ...
    strcmp(sourceControl.fastRestart,'off') && strcmp(checkpoint_storage_version(source),'-v7') && ...
    strcmp(checkpointreview.sha256(parent),sourceHash),'UpdateFrequency:Source','Unexpected source state or recipe.');
assert(sourceLength+limit*3000<capacity,'UpdateFrequency:Capacity','Source replay could be overwritten.');
[environment,manifest]=trainingenv.resolve(source);
modelHash=checkpointreview.sha256(environment);
courseHash=checkpointreview.sha256(fullfile(source,'curriculum.json'));
environmentHash=checkpointreview.sha256(fullfile(source,'environment.json'));
runtimeHash=checkpointreview.sha256(fullfile(root,'runtime','training_engine.m'));
routeHash=checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m'));
assert(strcmp(manifest.id,'spatial_v2') && ...
    strcmp(modelHash,'997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557') && ...
    strcmp(courseHash,'23104371dd53c55385b15bb2341f251a22c0b274bb7a92ea88552ecef0745682'), ...
    'UpdateFrequency:Snapshot','Unexpected parent environment or course.');
protocol=struct('schema_version',1,'source',source,'source_sha256',sourceHash, ...
    'source_episode',origin,'source_replay_length',sourceLength,'capacity',capacity, ...
    'environment_manifest_sha256',environmentHash,'model_sha256',modelHash, ...
    'curriculum_sha256',courseHash,'runtime_sha256',runtimeHash,'random_path_sha256',routeHash, ...
    'learning_frequencies',[1 2],'training_seed',trainingSeed,'episodes_per_arm',limit, ...
    'max_attempts_per_arm',1,'fresh_route_seeds',freshSeeds,'diagnostic_route_seed',diagnosticSeed, ...
    'expected_weak_wind',weakWind,'frozen_rollouts_per_checkpoint',2*numel(seeds), ...
    'scope','One training seed per arm. Same episode limit, potentially unequal interactions. No automatic selection, continuation, or stage promotion.');
protocolFile=fullfile(bundle,'protocol.json');
scenarioFile=fullfile(bundle,'scenario_preflight.mat');
if isfile(ledger)
    assert(isequaln(read(protocolFile),jsondecode(jsonencode(protocol))), ...
        'UpdateFrequency:Protocol','Existing prepared pair uses a different source, fixture or protocol.');
else
    state=struct('status','preparing','source_sha256',sourceHash,'current','', ...
        'children',struct('label',{},'learning_frequency',{},'session',{},'initial_sha256',{},'training',{}));
    write(protocolFile,protocol);
    write(ledger,state);
    try
        if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
        routeCases=verifyScenarios(source,seeds,weakWind);
        save(scenarioFile,'routeCases','-v7');
        state.scenario_preflight_sha256=checkpointreview.sha256(scenarioFile);
        write(ledger,state);
        audit=trainingtools.audit_sac_replay_retention(parent,parent);
        assert(audit.source_length==sourceLength && audit.source_capacity==capacity && audit.source_prefix_retained, ...
            'UpdateFrequency:Capacity','Unexpected replay at the source checkpoint.');
        write(fullfile(bundle,'source_replay.json'),audit);
        recipe=struct('schema_version',1,'checkpoint_episode',origin,'checkpoint_source','final', ...
            'expected_checkpoint_sha256',sourceHash,'actor_learning_rate_scale',1, ...
            'expected_actor_learning_rate',sourceModel.actorLearnRate,'experience_buffer_length',capacity, ...
            'episodes_per_process',limit,'max_additional_episodes',limit, ...
            'guard',struct('schema_version',1,'window',limit,'patience',3,'reward_ratio',.5, ...
            'steps_ratio',.5,'min_reference_reward',500,'min_reference_steps',500, ...
            'budget_enabled',true,'regression_action','pause'));
        for arm=1:2
            label=labels{arm};
            if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
            if arm==2
                recipe.checkpoint_source='final_learning_frequency';
                recipe.learning_frequency=2;
            end
            recipeFile=fullfile(bundle,[label '_recipe.json']);
            write(recipeFile,recipe);
            state.current=label;
            write(ledger,state);
            child=trainingtools.prepare_recovery_training(string(source),string(recipeFile));
            initial=fullfile(child.sessionDir,'checkpoints',sprintf('Agent%d.mat',origin));
            state.children(arm)=struct('label',label,'learning_frequency',arm, ...
                'session',char(child.sessionDir),'initial_sha256',checkpointreview.sha256(initial),'training',[]);
            write(ledger,state);
            ready=retry(resume=string(child.sessionDir),start=false,maxAttempts=1, ...
                episodesPerProcess=limit,checkpointEvery=limit,averageWindow=limit,maxNoProgressFailures=1);
            assert(isempty(ready.supervisor),'UpdateFrequency:Preparation','Preparation unexpectedly returned a supervisor.');
            write(fullfile(child.sessionDir,'experiment_protocol.json'), ...
                struct('training_seed',trainingSeed,'comparison_bundle',bundle,'arm',label));
        end
        verifyPair();
        state.status='prepared';state.current='';
        write(ledger,state);
    catch err
        recordFailure(err);
        rethrow(err);
    end
end
verifyPair();
assert(isfile(scenarioFile) && strcmp(checkpointreview.sha256(scenarioFile),state.scenario_preflight_sha256), ...
    'UpdateFrequency:Scenario','Prepared scenario fingerprints changed.');
if mode=="prepare"
    fprintf('Two new runs prepared. No training started.\n%s\n%s\n',state.children(1).session,state.children(2).session);
    return
end
if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
% Capability failures leave both verified runs prepared, without a launch intent.
write(fullfile(bundle,'capability.json'),trainingtools.preflight_sac_random('gpu',6));
scenarios=load(scenarioFile,'routeCases');
try
    for arm=1:2
        if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
        child=state.children(arm).session;
        state.status='training';state.current=labels{arm};
        write(ledger,state);
        info=retry(resume=string(child),start=true,maxAttempts=1,episodesPerProcess=limit);
        clock=tic;
        while ~info.supervisor.WaitForExit(1000)
            if toc(clock)>60
                fprintf('%s: waiting for the one bounded attempt in %s\n',labels{arm},child);
                clock=tic;
            end
        end
        cancelled=isfile(fullfile(bundle,'CANCEL'));
        if cancelled
            stopped=read(fullfile(child,'status.json'));
            if info.supervisor.ExitCode~=0 || ~strcmp(stopped.state,'paused')
                finishCancelled();return
            end
        end
        assert(info.supervisor.ExitCode==0,'UpdateFrequency:Process','Supervisor failed. Inspect this attempt.');
        state.children(arm).training=collectOutcome(child,bundle,labels{arm},arm,parent,protocol,sourceStage);
        write(ledger,state);
        if cancelled,finishCancelled();return;end
    end
    state.status='evaluation';state.current='';
    write(ledger,state);
    reports=cell(3,2);
    inputs={parent,state.children(1).training.final,state.children(2).training.final};
    expectedHashes={sourceHash,state.children(1).training.final_sha256,state.children(2).training.final_sha256};
    evalLabels=[{'source1700'} labels];
    for role=1:3
        if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
        fixture=makeEvaluationFixture(root,source,inputs{role},expectedHashes{role});
        for stage=1:2
            if isfile(fullfile(bundle,'CANCEL')),finishCancelled();return;end
            state.current=sprintf('%s_stage%d',evalLabels{role},stage);
            write(ledger,state);
            report=compare_training_checkpoints(string(fixture),episodes=[],includeLatest=false, ...
                finalCheckpoint=true,stages=stage,seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
            expectedEpisode=origin;
            if role>1,expectedEpisode=state.children(role-1).training.episodes;end
            validateEvaluation(report,protocol,expectedHashes{role},expectedEpisode,stage,seeds,scenarios.routeCases);
            destination=fullfile(bundle,evalLabels{role},sprintf('stage%d',stage));
            mkdir(destination);
            copyfile(fullfile(report.outputDir,'*'),destination);
            reports{role,stage}=report;
        end
    end
    comparison={};
    for stage=1:2
        stageRows=cellfun(@(r)structRows(r.results),reports(:,stage),'UniformOutput',false);
        common=seeds;
        for role=1:3
            rows=stageRows{role};
            full=([rows.steps]==3000 & ~[rows.environment_done]);
            common=intersect(common,[rows(full).seed],'stable');
        end
        for scope={'fresh','diagnostic'}
            for role=1:3
                rows=stageRows{role};
                isFresh=ismember([rows.seed],freshSeeds);
                if strcmp(scope{1},'fresh'),selected=rows(isFresh);else,selected=rows(~isFresh);end
                comparison{end+1}=summarize(selected,evalLabels{role},scope{1},common); %#ok<AGROW>
            end
        end
    end
    write(fullfile(bundle,'comparison.json'),comparison);
    assert(strcmp(checkpointreview.sha256(parent),sourceHash),'UpdateFrequency:Changed','Source checkpoint changed.');
    state.status='complete';state.current='';
    write(ledger,state);
    fprintf('Both branches remain paused. No winner was selected.\n');
catch err
    recordFailure(err);
    rethrow(err);
end

    function verifyPair()
        assert(numel(state.children)==2 && ~strcmp(state.children(1).session,state.children(2).session), ...
            'UpdateFrequency:Pair','Expected two distinct prepared children.');
        for k=1:2
            entry=state.children(k);
            child=entry.session;
            assert(strcmp(child,trainingtools.local_data_path(root,child)) && ...
                strcmp(fileparts(child),fileparts(source)) && ~strcmp(child,source) && ...
                entry.learning_frequency==k && strcmp(entry.label,labels{k}), ...
                'UpdateFrequency:Pair','Prepared receipt points outside the expected pair.');
            st=read(fullfile(child,'status.json'));cfg=read(fullfile(child,'control.json'));
            guard=read(fullfile(child,'training_guard.json'));lineage=read(fullfile(child,'recovery.json'));
            m=read(fullfile(child,'model.json'));expectedModel=sourceModel;expectedModel.learningFrequency=k;
            seed=read(fullfile(child,'experiment_protocol.json'));
            initial=fullfile(child,'checkpoints',sprintf('Agent%d.mat',origin));
            assert(strcmp(st.state,'paused') && st.attempt==0 && isfile(fullfile(child,'STOP')) && ...
                isempty(dir(fullfile(child,'attempt_*'))) && ~isfile(fullfile(child,'Agent_Final.mat')) && ...
                isequaln(m,expectedModel) && isequaln(read(fullfile(child,'curriculum_state.json')),sourceStage) && ...
                strcmp(checkpointreview.sha256(fullfile(child,'curriculum.json')),courseHash) && ...
                strcmp(checkpointreview.sha256(fullfile(child,'environment.json')),environmentHash) && ...
                strcmp(checkpointreview.sha256(fullfile(child,'environment','FAFA_Simulation.slx')),modelHash) && ...
                strcmp(checkpoint_storage_version(child),'-v7') && ...
                strcmp(cfg.sessionDir,child) && strcmp(cfg.modularRoot,root) && ...
                strcmp(cfg.scriptDir,fullfile(root,'runtime')) && strcmp(cfg.diagnosticDir,fullfile(child,'diagnostics')) && ...
                cfg.maxAttempts==1 && cfg.maxNoProgressFailures==1 && cfg.numWorkers==6 && cfg.minWorkers==6 && ...
                isempty(cfg.fallbackWorkers) && strcmp(cfg.fastRestart,'off') && ...
                strcmp(cfg.executionMode,'parallel') && strcmp(cfg.trainingDevice,'gpu') && ...
                cfg.checkpointEvery==limit && cfg.averageWindow==limit && cfg.episodesPerProcess==limit && ...
                guard.schema_version==1 && guard.max_additional_episodes==limit && ...
                guard.window==limit && guard.origin_episode==origin && guard.patience==3 && ...
                guard.reward_ratio==.5 && guard.steps_ratio==.5 && guard.min_reference_reward==500 && ...
                guard.min_reference_steps==500 && guard.budget_enabled && strcmp(guard.regression_action,'pause') && ...
                strcmp(lineage.parent_session,source) && strcmp(lineage.parent_checkpoint,parent) && ...
                strcmp(lineage.parent_sha256,sourceHash) && lineage.parent_episode==origin && ...
                strcmp(lineage.child_checkpoint_sha256,entry.initial_sha256) && ...
                strcmp(checkpointreview.sha256(initial),entry.initial_sha256) && ...
                seed.training_seed==trainingSeed && strcmp(seed.arm,entry.label) && strcmp(seed.comparison_bundle,bundle), ...
                'UpdateFrequency:Pair','Prepared configuration or identity differs from the declared trial.');
            if k==1
                assert(strcmp(entry.initial_sha256,sourceHash),'UpdateFrequency:Pair','F1 must be byte-identical to the parent.');
            end
        end
    end

    function finishCancelled()
        state.status='cancelled';
        write(ledger,state);
        fprintf('Cancellation found between bounded operations. No further attempt will start.\n');
    end

    function recordFailure(err)
        state.status='error';
        state.error=struct('identifier',err.identifier,'message',err.message);
        write(ledger,state);
    end
end

function result=collectOutcome(child,bundle,label,frequency,parent,protocol,sourceStage)
lock=lockFile(fullfile(child,'supervisor.lock'),System.IO.FileMode.Open);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
s=read(fullfile(child,'status.json'));
w=readtable(fullfile(child,'diagnostics','worker_attempts.csv'));
final=fullfile(child,'Agent_Final.mat');
[history,last]=checkpoint_resume_state(final);
outcome=read(fullfile(child,'curriculum_outcome.json'));
attemptDir=fullfile(child,'attempt_00001');
attempt=read(fullfile(attemptDir,'attempt.json'));
resultFile=read(fullfile(attemptDir,'result.json'));
environment=read(fullfile(attemptDir,'environment_used.json'));
initial=fullfile(child,'checkpoints',sprintf('Agent%d.mat',protocol.source_episode));
assert(strcmp(environment.id,'spatial_v2') && strcmp(environment.model_sha256,protocol.model_sha256) && ...
    strcmp(environment.engine_sha256,protocol.runtime_sha256) && ...
    strcmp(attempt.trainingDevice,'gpu') && strcmp(attempt.executionMode,'parallel') && ...
    strcmp(attempt.fastRestart,'off') && attempt.numWorkers==6 && attempt.minWorkers==6 && ...
    attempt.checkpointEvery==protocol.episodes_per_arm && attempt.episodesPerProcess==protocol.episodes_per_arm && ...
    strcmp(resultFile.resumeFile,initial) && resultFile.episodes==last && resultFile.pause && ...
    resultFile.stageIndex==2 && ~resultFile.success, ...
    'UpdateFrequency:AttemptIdentity','Actual execution did not match the prepared attempt.');
assert(strcmp(s.state,'paused') && height(w)==1 && w.ExitCode(1)==0 && w.ActualWorkers(1)==6 && ...
    last==outcome.episodes && last>protocol.source_episode && ...
    last<=protocol.source_episode+protocol.episodes_per_arm && ...
    isequaln(read(fullfile(child,'curriculum_state.json')),sourceStage), ...
    'UpdateFrequency:Outcome','Expected one saved attempt and an unchanged Stage 2.');
selected=history.EpisodeIndex>protocol.source_episode;
steps=double(history.EpisodeSteps(selected));
actor=double(history.ActorGradientSteps(selected));
critic=double(history.CriticGradientSteps(selected));
assert(~isempty(steps) && sum(steps)>0 && numel(actor)==numel(steps) && numel(critic)==numel(steps) && ...
    all(isfinite([steps(:);actor(:);critic(:)])) && all(diff(actor)>=0) && all(diff(critic)>=0), ...
    'UpdateFrequency:Counters','Invalid recorded counters.');
audit=trainingtools.audit_sac_replay_retention(parent,final);
assert(audit.source_length==protocol.source_replay_length && ...
    audit.candidate_capacity==protocol.capacity && audit.source_prefix_retained && ...
    audit.candidate_length==audit.source_length+sum(steps),'UpdateFrequency:Retention','Unexpected replay retention.');
loaded=load(final,'Agent_Stage2');
assert(loaded.Agent_Stage2.AgentOptions.LearningFrequency==frequency, ...
    'UpdateFrequency:Checkpoint','Saved learning frequency changed.');
result=struct('arm',label,'frequency',frequency,'episodes',last,'new_episodes',nnz(selected), ...
    'environment_steps',sum(steps),'actor_gradient_steps',actor(end),'critic_gradient_steps',critic(end), ...
    'actor_gradient_steps_per_environment_step',actor(end)/sum(steps), ...
    'critic_gradient_steps_per_environment_step',critic(end)/sum(steps), ...
    'counter_scope','Last saved cumulative value for this single attempt. No subtraction of inherited rows or sum of cumulative samples.', ...
    'saved_episode_index',history.EpisodeIndex(selected),'per_episode_environment_steps',steps, ...
    'actor_gradient_step_counter',actor,'critic_gradient_step_counter',critic, ...
    'final',final,'final_sha256',audit.candidate_sha256,'replay',audit,'outcome',outcome);
destination=fullfile(bundle,label);
mkdir(destination);
for name={'status.json','control.json','model.json','recovery.json','curriculum.json', ...
        'curriculum_state.json','curriculum_outcome.json','environment.json','training_guard.json', ...
        'training_guard_state.json','experiment_protocol.json','checkpoint_storage.json','Agent_Final.mat'}
    copyfile(fullfile(child,name{1}),destination);
end
mkdir(fullfile(destination,'attempt_00001'));
for pattern={'*.json','*.log'}
    files=dir(fullfile(child,'attempt_00001',pattern{1}));
    for k=1:numel(files)
        copyfile(fullfile(files(k).folder,files(k).name),fullfile(destination,'attempt_00001'));
    end
end
copyfile(fullfile(child,'diagnostics','worker_attempts.csv'),destination);
write(fullfile(destination,'training_metrics.json'),result);
end

function fixture=makeEvaluationFixture(root,source,checkpoint,hash)
cache=trainingtools.local_data_path(root,fullfile('artifacts','cache'));
if ~isfolder(cache),mkdir(cache);end
fixture=tempname(cache);mkdir(fixture);
for name={'curriculum.json','environment.json'}
    copyfile(fullfile(source,name{1}),fixture);
end
[model,manifest]=trainingenv.resolve(source);
mkdir(fullfile(fixture,'environment'));
for k=1:numel(manifest.files)
    name=manifest.files(k).name;
    copyfile(fullfile(fileparts(model),name),fullfile(fixture,'environment',name));
end
target=fullfile(fixture,'Agent_Final.mat');
copyfile(checkpoint,target);
assert(strcmp(checkpointreview.sha256(target),hash),'UpdateFrequency:Copy','Frozen source copy changed.');
write(fullfile(fixture,'status.json'),struct('state','paused'));
lock=lockFile(fullfile(fixture,'supervisor.lock'),System.IO.FileMode.CreateNew);
lock.Dispose();
end

function routeCases=verifyScenarios(source,seeds,weakWind)
global TARGET_SPEED DT WAYPOINT_SPACING
previous={TARGET_SPEED DT WAYPOINT_SPACING};
restore=onCleanup(@() restoreScenarioGlobals(previous)); %#ok<NASGU>
TARGET_SPEED=15; DT=0.1; WAYPOINT_SPACING=1.5;
course=trainingcurriculum.load_plan(fullfile(source,'curriculum.json'),true);
routeCases=cell(size(seeds));
for k=1:numel(seeds)
    calm=checkpointreview.scenario(course.stages{1},source,seeds(k));
    weak=checkpointreview.scenario(course.stages{2},source,seeds(k));
    assert(strcmp(calm.id,'random_calm') && strcmp(weak.id,'random_weak_wind') && ...
        calm.seed==seeds(k) && weak.seed==seeds(k) && ...
        isequal(calm.wind,[0 0 0]) && isequal(weak.wind,weakWind(k,:)) && ...
        isequal(calm.waypoints,weak.waypoints) && isequal(calm.velocity,weak.velocity), ...
        'UpdateFrequency:Scenario','Unexpected pairing or actual wind at seed %.0f.',seeds(k));
    routeCases{k}=calm;
end
end

function restoreScenarioGlobals(previous)
global TARGET_SPEED DT WAYPOINT_SPACING
[TARGET_SPEED,DT,WAYPOINT_SPACING]=previous{:};
end

function validateEvaluation(r,p,sha,episode,stage,seeds,routeCases)
ids={'random_calm','random_weak_wind'};
rows=structRows(r.results);checkpoints=structRows(r.checkpoints);
saved=load(fullfile(r.outputDir,'scenarios.mat'),'scenarios');
assert(iscell(saved.scenarios) && numel(saved.scenarios)==numel(seeds), ...
    'UpdateFrequency:Pairing','Wrong number of saved scenarios.');
assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && ...
    r.route_metrics_enabled && strcmp(r.device,'cpu') && r.max_steps==3000 && ...
    strcmp(r.curriculum_sha256,p.curriculum_sha256) && strcmp(r.model_sha256,p.model_sha256) && ...
    strcmp(r.runtime_sha256,p.runtime_sha256) && strcmp(r.random_path_sha256,p.random_path_sha256) && ...
    isscalar(checkpoints) && checkpoints.episode==episode && strcmp(checkpoints.sha256,sha) && ...
    numel(rows)==numel(seeds) && isequal(sort([rows.seed]),sort(seeds)), ...
    'UpdateFrequency:Evaluation','Frozen provenance or coverage differs.');
for k=1:numel(seeds)
    row=rows([rows.seed]==seeds(k) & strcmp({rows.stage_id},ids{stage}));
    wind=[0 0 0];
    if stage==2,wind=p.expected_weak_wind(k,:);end
    scenario=saved.scenarios{k};
    route=routeCases{k};
    assert(isscalar(row) && row.checkpoint_episode==episode && ...
        isequal([row.wind_east_mps row.wind_north_mps row.turbulence],wind) && ...
        scenario.seed==seeds(k) && strcmp(scenario.id,ids{stage}) && isequal(scenario.wind,wind) && ...
        isequal(scenario.waypoints,route.waypoints) && isequal(scenario.velocity,route.velocity), ...
        'UpdateFrequency:Pairing','Frozen stage, seed or actual wind differs.');
end
end

function row=summarize(rows,arm,scope,common)
metrics=arrayfun(@(r)r.route_metrics.after_10_seconds,rows);
full=([rows.steps]==3000 & ~[rows.environment_done]);
included=ismember([rows.seed],common);
rms=[metrics(included).rms_m];peaks=[metrics(included).max_m];
row=struct('arm',arm,'seed_group',scope,'stage',rows(1).stage_id, ...
    'count',numel(rows),'full_count',nnz(full),'mean_steps',mean([rows.steps]), ...
    'reward_mean',mean([rows.reward]),'common_full_count',nnz(included), ...
    'common_full_seeds',[rows(included).seed],'common_late_rms_mean_m',mean(rms,'omitnan'), ...
    'common_late_peak_mean_m',mean(peaks,'omitnan'), ...
    'common_late_peak_max_m',max(peaks,[],'omitnan'));
end

function rows=structRows(rows)
if iscell(rows),rows=[rows{:}];end
end

function lock=lockFile(path,mode)
lock=System.IO.File.Open(path,mode,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
end

function data=read(file)
data=jsondecode(fileread(file));
end

function write(file,data)
trainingcurriculum.write_json(file,data);
end
