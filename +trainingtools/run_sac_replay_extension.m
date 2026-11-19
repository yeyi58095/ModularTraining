function bundle=run_sac_replay_extension()
% One 50-episode child from the reviewed 500k final, then frozen evaluation.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
bundle=fullfile(root,'artifacts','packages','sac-replay-extension-20261119');if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledger=fullfile(bundle,'review.json');
if isfile(ledger)
    prior=read(ledger);if any(strcmp(prior.status,{'complete','cancelled'})),fprintf('Already finished; package only.\n');return;end
    assert(~prior.prepare_intent,'ReplayExtension:Interrupted','Preparation recorded; package and inspect instead of relaunching.');
end
state=struct('status','preflight','prepare_intent',false,'children',{{}});write(ledger,state);
try
    source=fullfile(root,'experiments','sac_random_route_v1','runs','20261119_004245_recovery_tpf24d3776');
    file=fullfile(source,'Agent_Final.mat');sha='a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6';
    s=read(fullfile(source,'status.json'));m=read(fullfile(source,'model.json'));cfg=read(fullfile(source,'control.json'));
    o=read(fullfile(source,'curriculum_outcome.json'));stage=read(fullfile(source,'curriculum_state.json'));
    assert(strcmp(s.state,'paused') && o.episodes==1700 && strcmp(o.curriculumReason,'recovery_budget') && ...
        stage.stage_index==2 && stage.start_episode==1000 && strcmp(m.name,'sac_paper64') && ...
        m.actorLearnRate==1.5e-4 && m.criticLearnRate==3e-4 && m.experienceBufferLength==500000 && ...
        strcmp(cfg.trainingDevice,'gpu') && strcmp(cfg.executionMode,'parallel') && cfg.numWorkers==6 && cfg.minWorkers==6, ...
        'ReplayExtension:Source','Unexpected source or settings.');
    assert(strcmp(checkpointreview.sha256(file),sha),'ReplayExtension:Hash','Reviewed final changed.');
    seeds=[2000011501:2000011510 2000011801:2000011810 2000011901:2000011920];
    folders={'sac-replay-replication-20261118','sac-replay-holdout-20261119'};reports=cell(1,2);
    for k=1:2
        parent=fullfile(root,'artifacts','packages',folders{k});q=read(fullfile(parent,'review.json'));assert(strcmp(q.status,'complete'));
        label='retained500k';if k==1,label='retained500k_evaluation';end
        reports{k}=read(fullfile(parent,label,'evaluation.json'));validate(reports{k},seeds((k-1)*20+(1:20)),sha,1700);
        assert(strcmp(checkpointreview.sha256(fullfile(source,'curriculum.json')),reports{k}.curriculum_sha256), ...
            'ReplayExtension:Curriculum','Source curriculum changed since frozen evaluation.');
        a=rows(reports{k});assert(all([a.steps]==3000 & ~[a.environment_done]),'ReplayExtension:Evidence','Expected reviewed 40/40 in each set.');
        write(fullfile(bundle,sprintf('parent_set%d.json',k)),reports{k});
    end
    audit=trainingtools.audit_sac_replay_retention(file,file);
    assert(audit.source_length==337132 && audit.candidate_capacity==500000 && audit.source_length+50*3000<=500000, ...
        'ReplayExtension:Capacity','50-episode retention bound does not hold.');
    write(fullfile(bundle,'source_replay.json'),audit);
    write(fullfile(bundle,'capability.json'),trainingtools.preflight_sac_random('gpu',6));
    write(fullfile(bundle,'protocol.json'),struct('source',source,'source_sha256',sha,'source_episode',1700, ...
        'max_additional_episodes',50,'training_seed',20261120,'replay_capacity',500000,'source_replay_length',337132, ...
        'max_expected_replay_length',487132,'evaluation_seeds',seeds,'automatic_continuation',false, ...
        'scope','One child, no parameter change. Previously inspected 40 routes x two stages after training; not new holdout. No stage advancement or automatic next attempt.'));
    if cancelled(),return;end
    recipe=struct('schema_version',1,'checkpoint_episode',1700,'checkpoint_source','final','expected_checkpoint_sha256',sha, ...
        'actor_learning_rate_scale',1,'expected_actor_learning_rate',1.5e-4,'experience_buffer_length',500000, ...
        'episodes_per_process',50,'max_additional_episodes',50, ...
        'guard',struct('schema_version',1,'window',50,'patience',3,'reward_ratio',.5,'steps_ratio',.5,'min_reference_reward',500,'min_reference_steps',500));
    recipeFile=fullfile(bundle,'recipe.json');write(recipeFile,recipe);
    state.prepare_intent=true;state.status='preparing';write(ledger,state);
    info=trainingtools.prepare_recovery_training(string(source),string(recipeFile));child=info.sessionDir;
    state.children={struct('label','continued500k','session',child)};state.current='continued500k';write(ledger,state);
    assert(strcmp(checkpointreview.sha256(fullfile(child,'checkpoints','Agent1700.mat')),sha),'ReplayExtension:Copy','Prepared checkpoint must be byte-identical.');
    g=read(fullfile(child,'training_guard.json'));cc=read(fullfile(child,'control.json'));
    assert(g.origin_episode==1700 && g.max_additional_episodes==50 && cc.checkpointEvery==50 && cc.episodesPerProcess==50,'ReplayExtension:Budget','Unexpected budget.');
    write(fullfile(child,'experiment_protocol.json'),struct('training_seed',20261120,'comparison_bundle',bundle,'arm','continued500k'));
    if cancelled(),return;end
    state.status='training';write(ledger,state);
    info=retry(resume=string(child),start=true,maxAttempts=1,episodesPerProcess=50);clock=tic;
    while ~info.supervisor.WaitForExit(1000)
        if toc(clock)>60,fprintf('Bounded 50-episode attempt: %s\n',child);clock=tic;end
    end
    assert(info.supervisor.ExitCode==0,'ReplayExtension:Process','Supervisor failed; do not retry.');
    s=read(fullfile(child,'status.json'));w=readtable(fullfile(child,'diagnostics','worker_attempts.csv'));
    [h,last]=checkpoint_resume_state(fullfile(child,'Agent_Final.mat'));outcome=read(fullfile(child,'curriculum_outcome.json'));
    stage=read(fullfile(child,'curriculum_state.json'));
    assert(strcmp(s.state,'paused') && height(w)==1 && w.ExitCode(end)==0 && last>1700 && last<=1750 && outcome.episodes==last && stage.stage_index==2,'ReplayExtension:Stop','Unexpected saved outcome.');
    state.children{1}.outcome=outcome;state.children{1}.added_episodes=last-1700;state.children{1}.new_steps=sum(h.EpisodeSteps(1701:end));write(ledger,state);
    collect(child,fullfile(bundle,'continued500k'));
    audit=trainingtools.audit_sac_replay_retention(file,fullfile(bundle,'continued500k','Agent_Final.mat'));write(fullfile(bundle,'final_replay.json'),audit);
    assert(audit.source_prefix_retained && audit.candidate_length==337132+state.children{1}.new_steps && audit.candidate_length<=487132 && audit.candidate_capacity==500000,'ReplayExtension:Retention','Replay retention failed.');
    if cancelled(),return;end
    state.status='evaluation';write(ledger,state);
    r=compare_training_checkpoints(string(child),episodes=[],includeLatest=false,finalCheckpoint=true, ...
        stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
    validate(r,seeds,checkpointreview.sha256(fullfile(bundle,'continued500k','Agent_Final.mat')),last);
    for k=1:2,verifyPair(reports{k},r);end
    target=fullfile(bundle,'continued500k_evaluation');mkdir(target);copyfile(fullfile(r.outputDir,'*'),target);
    comparison={};a=rows(r);
    for k=1:2
        b=rows(reports{k});
        for st={'random_calm','random_weak_wind'}
            x=a(strcmp({a.stage_id},st{1}) & ismember([a.seed],[b.seed]));d=arrayfun(@(v)v.route_metrics.after_10_seconds,x);
            full=[x.steps]==3000 & ~[x.environment_done];wind=[x.wind_east_mps]~=0 | [x.wind_north_mps]~=0 | [x.turbulence]~=0;
            comparison{end+1}=struct('arm','continued500k','stage',st{1},'seed_group',k,'count',20,'full_count',sum(full), ...
                'mean_steps',mean([x.steps]),'actual_wind_count',sum(wind),'actual_wind_full',sum(full & wind), ...
                'late_rms_mean_m',mean([d.rms_m]),'late_max_m',max([d.max_m]),'full_and_rms10_max20_count',sum(full & [d.rms_m]<=10 & [d.max_m]<=20)); %#ok<AGROW>
        end
    end
    write(fullfile(bundle,'comparison.json'),comparison);state.status='complete';write(ledger,state);
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');
    if ~isempty(state.children)
        try,collect(state.children{1}.session,fullfile(bundle,'continued500k'));catch e,state.collection_error=e.message;end
    end
    write(ledger,state);rethrow(err);
end
fprintf('Extension complete; child stays paused. No automatic continuation.\n');
    function yes=cancelled()
        yes=isfile(fullfile(bundle,'CANCEL'));if yes,state.status='cancelled';write(ledger,state);end
    end
end
function validate(r,seeds,sha,ep)
cp=r.checkpoints;if iscell(cp),cp=[cp{:}];end
assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && r.max_steps==3000 && numel(cp)==1 && strcmp(cp.sha256,sha) && cp.episode==ep,'ReplayExtension:Evaluation','Wrong report/checkpoint.');
a=rows(r);assert(numel(a)==2*numel(seeds));
for st={'random_calm','random_weak_wind'},x=a(strcmp({a.stage_id},st{1}));assert(isequal(sort([x.seed]),sort(seeds)));end
end
function verifyPair(before,after)
for key={'curriculum_sha256','model_sha256','runtime_sha256','random_path_sha256','guidance_variant'},assert(strcmp(before.(key{1}),after.(key{1})),'ReplayExtension:Environment','Environment changed.');end
a=rows(before);b=rows(after);
for j=1:numel(a)
    x=b([b.seed]==a(j).seed & strcmp({b.stage_id},a(j).stage_id));assert(numel(x)==1 && isequal([x.wind_east_mps x.wind_north_mps x.turbulence],[a(j).wind_east_mps a(j).wind_north_mps a(j).turbulence]),'ReplayExtension:Wind','Pair differs.');
end
end
function collect(child,target)
lock=System.IO.File.Open(fullfile(child,'supervisor.lock'),System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);c=onCleanup(@()lock.Dispose()); %#ok<NASGU>
if ~isfolder(target),mkdir(target);end
for name=["control.json","status.json","model.json","recovery.json","curriculum.json","environment.json","curriculum_state.json","curriculum_outcome.json","training_guard.json","training_guard_state.json","experiment_protocol.json","Agent_Final.mat"]
    if isfile(fullfile(child,name)),copyfile(fullfile(child,name),target);end
end
if isfolder(fullfile(child,'attempt_00001')),copyfile(fullfile(child,'attempt_00001'),fullfile(target,'attempt_00001'));end
if isfile(fullfile(child,'diagnostics','worker_attempts.csv')),copyfile(fullfile(child,'diagnostics','worker_attempts.csv'),target);end
end
function a=rows(r),a=r.results;if iscell(a),a=[a{:}];end,end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
