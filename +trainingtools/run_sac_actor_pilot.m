function bundle=run_sac_actor_pilot(mode)
% Two sequential, independently forked 100-episode trials. Never long-run.
arguments
    mode (1,1) string {mustBeMember(mode,["actor","replay_retention"])} = "actor"
end
replayPilot=mode=="replay_retention";
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
bundle=fullfile(root,'artifacts','packages','sac-actor-pilot-20261116');
if replayPilot,bundle=fullfile(root,'artifacts','packages','sac-replay-retention-20261118');end
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledgerFile=fullfile(bundle,'review.json');
if isfile(ledgerFile)
    previous=read(ledgerFile);
    if any(strcmp(previous.status,{'complete','cancelled'})),fprintf('Already finished; package only.\n');return;end
    assert(~isfield(previous,'prepare_intent') || ~previous.prepare_intent, ...
        'ActorPilot:Interrupted','Preparation/launch recorded. Package and inspect; never automatically repeat.');
end
state=struct('status','preflight','prepare_intent',false,'children',{{}}, ...
    'scope','Hypothesis test, not a proven fix. Two 100-episode branches; no automatic winner continuation.');
write(ledgerFile,state);
try
    source=fullfile(root,'experiments','sac_random_route_v1','runs','20261114_211021_recovery_tp4c32126b');
    parent=read(fullfile(source,'status.json'));model=read(fullfile(source,'model.json'));
    outcome=read(fullfile(source,'curriculum_outcome.json'));cfg=read(fullfile(source,'control.json'));
    assert(strcmp(parent.state,'paused') && outcome.episodes==2100 && ...
        strcmp(outcome.curriculumReason,'recovery_budget') && strcmp(model.name,'sac_paper64') && ...
        model.actorLearnRate==1.5e-4 && model.criticLearnRate==3e-4 && ...
        strcmp(cfg.trainingDevice,'gpu') && strcmp(cfg.executionMode,'parallel') && ...
        cfg.numWorkers==6 && cfg.minWorkers==6,'ActorPilot:Source','Unexpected parent or execution settings.');
    checkpoint=fullfile(source,'checkpoints','Agent1600.mat');sha=checkpointreview.sha256(checkpoint);
    assert(strcmp(sha,'45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c'), ...
        'ActorPilot:Source','Wrong Agent1600.');
    capability=trainingtools.preflight_sac_random('gpu',6);write(fullfile(bundle,'capability.json'),capability);
    seeds=[2000011501:2000011510 2000011601:2000011610];
    actorRates=[1.5e-4 7.5e-5];capacities=[50000 50000];trainingSeed=20261116;
    labels={'baseline','actor_half'};
    if replayPilot
        assert(model.experienceBufferLength==50000,'ReplayPilot:Source','Expected 50k source replay.');
        seeds=[2000011501:2000011510 2000011801:2000011810];
        actorRates=[1.5e-4 1.5e-4];capacities=[50000 500000];trainingSeed=20261118;
        labels={'baseline50k','retained500k'};
    end
    protocol=struct('source',source,'source_sha256',sha,'episodes_per_branch',100, ...
        'actor_rates',actorRates,'replay_capacities',capacities,'critic_rate',3e-4,'training_seed',trainingSeed, ...
        'diagnostic_seeds',seeds(1:10),'fresh_seeds',seeds(11:20), ...
        'interpretation','Matched initial agent and requested training seed; trajectories, noise timing and update counts need not match. Equal episodes, not equal environment steps.');
    if replayPilot
        protocol.hypothesis='Retaining initial replay may preserve frozen performance; capacity also changes sampling distribution, so this does not isolate every replay mechanism.';
        protocol.screening='No auto continuation. Candidate: each stage full count no more than one below reference and mean steps >=95% reference, plus more pooled full flights than fresh 50k baseline. Single training seed is not confirmation.';
    end
    write(fullfile(bundle,'protocol.json'),protocol);
    comparison={};
    r=evaluate(source,1600,false,seeds,fullfile(bundle,'reference1600'));
    reference=r;
    comparison=[comparison summarize(r,'reference1600',seeds)];write(fullfile(bundle,'comparison.json'),comparison);
    for k=1:2
        if isfile(fullfile(bundle,'CANCEL')),state.status='cancelled';write(ledgerFile,state);return;end
        recipe=struct('schema_version',1,'checkpoint_episode',1600,'expected_checkpoint_sha256',sha, ...
            'actor_learning_rate_scale',actorRates(k)/1.5e-4,'expected_actor_learning_rate',1.5e-4, ...
            'experience_buffer_length',capacities(k),'episodes_per_process',100,'max_additional_episodes',100, ...
            'guard',struct('schema_version',1,'window',100,'patience',3,'reward_ratio',.5, ...
            'steps_ratio',.5,'min_reference_reward',500,'min_reference_steps',500));
        recipeFile=fullfile(bundle,[labels{k} '_recipe.json']);write(recipeFile,recipe);
        state.status='preparing';state.prepare_intent=true;state.current=labels{k};write(ledgerFile,state);
        info=trainingtools.prepare_recovery_training(string(source),string(recipeFile));child=info.sessionDir;
        item=struct('label',labels{k},'session',child,'launch_intent',false);
        state.children{end+1}=item;write(ledgerFile,state);
        write(fullfile(child,'experiment_protocol.json'),struct('training_seed',protocol.training_seed, ...
            'comparison_bundle',bundle,'arm',labels{k}));
        guard=read(fullfile(child,'training_guard.json'));childModel=read(fullfile(child,'model.json'));
        assert(guard.origin_episode==1600 && guard.max_additional_episodes==100 && ...
            childModel.actorLearnRate==protocol.actor_rates(k),'ActorPilot:Budget','Unexpected prepared settings.');
        if replayPilot
            assert(childModel.experienceBufferLength==capacities(k) && childModel.criticLearnRate==3e-4, ...
                'ReplayPilot:Settings','Unexpected replay or critic settings.');
            prepared=trainingtools.audit_sac_replay_retention(checkpoint,fullfile(child,'checkpoints','Agent1600.mat'));
            write(fullfile(bundle,[labels{k} '_prepared_replay.json']),prepared);
            assert(prepared.source_prefix_retained && prepared.candidate_length==prepared.source_length && ...
                prepared.source_length==50000 && prepared.candidate_capacity==capacities(k), ...
                'ReplayPilot:Preparation','Prepared replay differs from source.');
        end
        if isfile(fullfile(bundle,'CANCEL')),state.status='cancelled';write(ledgerFile,state);return;end
        state.children{k}.launch_intent=true;state.status='training';write(ledgerFile,state);
        info=retry(resume=string(child),start=true,maxAttempts=1,episodesPerProcess=100);
        state.children{k}.supervisor_pid=double(info.supervisor.Id);write(ledgerFile,state);
        clock=tic;
        while ~info.supervisor.WaitForExit(1000)
            if toc(clock)>60,fprintf('%s: bounded attempt running. %s\n',labels{k},child);clock=tic;end
        end
        assert(info.supervisor.ExitCode==0,'ActorPilot:Process','Supervisor failed; do not retry.');
        s=read(fullfile(child,'status.json'));
        assert(strcmp(s.state,'paused'),'ActorPilot:Stop','Expected normal paused result.');
        workers=readtable(fullfile(child,'diagnostics','worker_attempts.csv'));
        assert(height(workers)==1 && workers.ExitCode(end)==0,'ActorPilot:Attempt','Expected one normal attempt.');
        result=read(fullfile(child,'attempt_00001','result.json'));
        [history,last]=checkpoint_resume_state(fullfile(child,'Agent_Final.mat'));
        assert(last==result.episodes && last>1600 && last<=1700,'ActorPilot:Budget','Unexpected saved progress.');
        stage=read(fullfile(child,'curriculum_state.json'));assert(stage.stage_index==2,'ActorPilot:Stage','Unexpected stage transition.');
        state.children{k}.outcome=result;state.children{k}.added_episodes=last-1600;
        state.children{k}.new_steps=sum(history.EpisodeSteps(1601:end));
        state.children{k}.mean_reward=mean(history.EpisodeReward(1601:end));
        write(ledgerFile,state);collect(child,fullfile(bundle,labels{k}));
        if replayPilot
            retained=trainingtools.audit_sac_replay_retention(checkpoint,fullfile(bundle,labels{k},'Agent_Final.mat'));
            write(fullfile(bundle,[labels{k} '_final_replay.json']),retained);
            assert(retained.candidate_capacity==capacities(k),'ReplayPilot:Capacity','Capacity changed.');
            if k==2
                assert(retained.source_prefix_retained,'ReplayPilot:Retention', ...
                    'Initial experience was not retained; hypothesis test invalid. Keep paused.');
            end
        end
        if isfile(fullfile(bundle,'CANCEL')),state.status='cancelled';write(ledgerFile,state);return;end
        state.status='evaluation';write(ledgerFile,state);
        r=evaluate(child,[],true,seeds,fullfile(bundle,[labels{k} '_evaluation']));
        verifyPair(reference,r);
        comparison=[comparison summarize(r,labels{k},seeds)];write(fullfile(bundle,'comparison.json'),comparison);
        if ~strcmp(result.curriculumReason,'recovery_budget')
            state.status='stopped_early';write(ledgerFile,state);return;
        end
    end
    if replayPilot
        baseline=read(fullfile(bundle,'baseline50k_evaluation','evaluation.json'));
        candidate=read(fullfile(bundle,'retained500k_evaluation','evaluation.json'));
        screening=screenReplay(reference,baseline,candidate);
        write(fullfile(bundle,'screening.json'),screening);
    end
    state.status='complete';write(ledgerFile,state);
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');
    for k=1:numel(state.children)
        try
            collect(state.children{k}.session,fullfile(bundle,state.children{k}.label));
        catch collectionError
            state.children{k}.collection_error=collectionError.message;
        end
    end
    write(ledgerFile,state);rethrow(err);
end
fprintf('Pilot complete. Both branches stay paused. No automatic winner continuation.\n');
end
function verifyPair(a,b)
for key={'curriculum_sha256','model_sha256','runtime_sha256','random_path_sha256','guidance_variant'}
    assert(strcmp(a.(key{1}),b.(key{1})),'ActorPilot:Environment','Paired evaluation environment differs.');
end
x=a.results;if iscell(x),x=[x{:}];end;y=b.results;if iscell(y),y=[y{:}];end
for k=1:numel(x)
    pair=y([y.seed]==x(k).seed & strcmp({y.stage_id},x(k).stage_id));
    assert(numel(pair)==1 && isequal([pair.wind_east_mps pair.wind_north_mps pair.turbulence], ...
        [x(k).wind_east_mps x(k).wind_north_mps x(k).turbulence]),'ActorPilot:Pairs','Wind pairing mismatch.');
end
end
function r=evaluate(session,ep,final,seeds,destination)
r=compare_training_checkpoints(string(session),episodes=ep,includeLatest=false,finalCheckpoint=final, ...
    stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && ...
    r.max_steps==3000 && numel(r.results)==40,'ActorPilot:Evaluation','Incomplete evaluation.');
rows=r.results;if iscell(rows),rows=[rows{:}];end
for id={'random_calm','random_weak_wind'}
    a=rows(strcmp({rows.stage_id},id{1}));assert(isequal(sort([a.seed]),sort(seeds)),'ActorPilot:Pairs','Missing paired rows.');
end
if ~isfolder(destination),mkdir(destination);end
copyfile(fullfile(r.outputDir,'*'),destination);
end
function out=summarize(r,label,seeds)
rows=r.results;if iscell(rows),rows=[rows{:}];end;out={};
for stage={'random_calm','random_weak_wind'}
    for group=1:2
        chosen=seeds((group-1)*10+(1:10));a=rows(strcmp({rows.stage_id},stage{1}) & ismember([rows.seed],chosen));
        full=[a.steps]==3000 & ~[a.environment_done];wind=[a.wind_east_mps]~=0 | [a.wind_north_mps]~=0 | [a.turbulence]~=0;
        out{end+1}=struct('arm',label,'stage',stage{1},'seed_group',group,'count',numel(a), ...
            'full_count',sum(full),'mean_steps',mean([a.steps]),'mean_reward',mean([a.reward]), ...
            'actual_wind_count',sum(wind),'actual_wind_full',sum(full & wind)); %#ok<AGROW>
    end
end
end
function collect(child,destination)
lock=System.IO.File.Open(fullfile(child,'supervisor.lock'),System.IO.FileMode.Open, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);c=onCleanup(@() lock.Dispose()); %#ok<NASGU>
if ~isfolder(destination),mkdir(destination);end
for name=["control.json","status.json","model.json","recovery.json","curriculum.json","environment.json", ...
        "curriculum_state.json","curriculum_outcome.json","training_guard.json","training_guard_state.json", ...
        "experiment_protocol.json","Agent_Final.mat"]
    copyfile(fullfile(child,name),fullfile(destination,name));
end
copyfile(fullfile(child,'attempt_00001'),fullfile(destination,'attempt_00001'));
copyfile(fullfile(child,'diagnostics','worker_attempts.csv'),fullfile(destination,'worker_attempts.csv'));
end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
function report=screenReplay(reference,baseline,candidate)
reports={reference,baseline,candidate};full=zeros(3,2);steps=zeros(3,2);
ids={'random_calm','random_weak_wind'};
for k=1:3
    a=reports{k}.results;if iscell(a),a=[a{:}];end
    for stage=1:2
        x=a(strcmp({a.stage_id},ids{stage}));assert(numel(x)==20);
        full(k,stage)=sum([x.steps]==3000 & ~[x.environment_done]);steps(k,stage)=mean([x.steps]);
    end
end
countGate=all(full(3,:)>=full(1,:)-1);stepsGate=all(steps(3,:)>=.95*steps(1,:));
baselineGate=sum(full(3,:))>sum(full(2,:));
report=struct('arms',{{'reference1600','baseline50k','retained500k'}},'stages',{ids}, ...
    'full_counts',full,'mean_steps',steps,'source_count_preserved',countGate, ...
    'source_steps_preserved',stepsGate,'more_full_than_baseline',baselineGate, ...
    'screen_pass',countGate && stepsGate && baselineGate,'automatic_continuation',false, ...
    'interpretation','Predeclared feasibility screen, not statistical evidence, original stage qualification, or authorization to continue. Review fresh-route subgroup and distance metrics separately.');
end
