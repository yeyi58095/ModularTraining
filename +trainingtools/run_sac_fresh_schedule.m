function bundle=run_sac_fresh_schedule(mode)
% Prepare, or explicitly execute, one independent scheduled four-wind SAC run.
arguments
    mode (1,1) string {mustBeMember(mode,["prepare","run"])} = "prepare"
end
root=fileparts(fileparts(mfilename('fullpath')));
runtime=fullfile(root,'runtime');
previousPath=path;
restorePath=onCleanup(@() path(previousPath)); %#ok<NASGU>
addpath(root,runtime,'-begin');
bundle=fullfile(root,'artifacts','packages','sac-fresh-schedule-20261121');
if ~isfolder(bundle),mkdir(bundle);end
bundleLock=openLock(fullfile(bundle,'schedule.lock'),System.IO.FileMode.OpenOrCreate);
releaseBundle=onCleanup(@() bundleLock.Dispose()); %#ok<NASGU>
ledgerFile=fullfile(bundle,'schedule.json');
protocolFile=fullfile(bundle,'protocol.json');
officialSource=fullfile(root,'experiments','sac_random_route_v1','curriculum.json');
officialFile=fullfile(bundle,'official_curriculum.json');
scheduleFile=fullfile(bundle,'sac_fresh_schedule_v1.json');
runParent=fullfile(root,'experiments','sac_fresh_schedule_v1','runs');
profile='sac_paper64_fresh500k';
quota=[1000 400 300 300];
limits=cumsum(quota);
interval=100;
workers=6;
seed=20261203;
assert(strcmp(version('-release'),'2024b'),'FreshSchedule:Release','This run requires MATLAB R2024b.');

if isfile(ledgerFile)
    ledger=read(ledgerFile);
    if any(strcmp(ledger.status,{'complete','guard_paused','cancelled'}))
        fprintf('Schedule already ended with status %s. Evidence is in %s\n',ledger.status,bundle);
        return
    end
    assert(strcmp(ledger.status,'prepared'),'FreshSchedule:Interrupted', ...
        'A prior preparation or run needs inspection. Automatic duplicate launches are disabled.');
end

officialPlan=trainingcurriculum.load_plan(officialSource,true);
assert(strcmp(officialPlan.model,'sac_paper64') && strcmp(officialPlan.environment,'spatial_v2') && ...
    numel(officialPlan.stages)==numel(quota),'FreshSchedule:Course','Unexpected official source course.');
schedule=officialPlan;
schedule.model=profile;
for stage=1:numel(quota)
    entry=rmfield(schedule.stages{stage},'frozen_gate');
    % The episode budget names the scheduled transition. The original gate is assessed separately.
    entry.advance_when=struct('metric','stage_episodes','at_least',quota(stage)+1);
    entry.max_episodes=quota(stage);
    entry.on_limit='advance';
    if stage==numel(quota),entry.on_limit='pause';end
    schedule.stages{stage}=entry;
end
spec=trainingmodels.load_profile(profile);
assert(strcmp(spec.name,profile) && strcmp(spec.algorithm,'SAC') && spec.experienceBufferLength==500000, ...
    'FreshSchedule:Profile','Unexpected fresh SAC profile.');
[envFile,envDir]=trainingenv.registry(root,'spatial_v2');
environment=trainingenv.verify(envFile,envDir);
envHash=checkpointreview.sha256(fullfile(envDir,environment.model_file));
officialHash=checkpointreview.sha256(officialSource);
engineHash=checkpointreview.sha256(fullfile(runtime,'training_engine.m'));
modelSource=fullfile(root,'+trainingmodels');
modelFiles=[{'build_agent.m','build_sac.m','paper_sac_networks.m','scale_std_actor.m', ...
    'validate_agent.m','validate_sac.m'}, {fullfile(profile,[profile '.m'])}];
modelHashes=cellfun(@(f) checkpointreview.sha256(fullfile(modelSource,f)),modelFiles,'UniformOutput',false);
rules=read(fullfile(root,'configs','recovery_actor_half.json'));
guard=rules.guard;
guard.origin_episode=0;
guard.max_additional_episodes=limits(end)+interval;
guard.budget_enabled=true;
guard.regression_action='pause';
runProtocol=struct('schema_version',1,'kind','fresh_scheduled_four_wind_feasibility', ...
    'training_seed',seed,'schedule_bundle',bundle,'stage_episode_quotas',quota, ...
    'official_curriculum_sha256',officialHash, ...
    'initialization','new SAC agent, replay and optimizer at episode 0; same agent across stages', ...
    'scope','Fixed episode budgets drive this feasibility schedule. Official criteria are audited independently.');
protocol=struct('schema_version',1,'experiment',runProtocol,'model',spec, ...
    'scheduled_end_episodes',limits,'total_episode_limit',limits(end), ...
    'total_step_upper_bound',limits(end)*3000,'max_training_attempts',numel(quota), ...
    'workers_requested',workers,'device_requested','gpu','execution_mode','parallel', ...
    'fast_restart','off','checkpoint_every',interval,'checkpoint_file_version','-v7', ...
    'environment_model_sha256',envHash,'environment_manifest',environment, ...
    'runtime_sha256',engineHash,'random_path_sha256',checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')), ...
    'model_source_files',{modelFiles},'model_source_sha256',{modelHashes},'training_guard',guard);

if ~isfile(ledgerFile)
    ledger=struct('status','preparing','session','','current_stage',0,'stages',{{}});
    write(ledgerFile,ledger);
    try
        if cancelled(bundle,''),finishCancelled();return;end
        assert(~isfile(protocolFile) && ~isfile(scheduleFile) && ~isfile(officialFile), ...
            'FreshSchedule:Interrupted','Schedule provenance already exists without a completed preparation.');
        copyfile(officialSource,officialFile);
        write(scheduleFile,schedule);
        write(protocolFile,protocol);
        info=retry(curriculum=scheduleFile,environment='spatial_v2',executionMode='parallel', ...
            device='gpu',workers=workers,minWorkers=workers,fallbackWorkers=[],fastRestart='off', ...
            episodesPerProcess=max(quota),checkpointEvery=interval,averageWindow=interval, ...
            maxAttempts=1,maxNoProgressFailures=1,start=false);
        assert(isempty(info.supervisor),'FreshSchedule:Prepare','Preparation returned a training supervisor.');
        ledger.session=char(info.sessionDir);
        write(ledgerFile,ledger);
        assertSession(ledger.session,runParent);
        write(fullfile(ledger.session,'experiment_protocol.json'),runProtocol);
        write(fullfile(ledger.session,'training_guard.json'),guard);
        write(fullfile(ledger.session,'checkpoint_storage.json'),struct('schema_version',1,'version','-v7'));
        ledger.scheduled_curriculum_sha256=checkpointreview.sha256(fullfile(ledger.session,'curriculum.json'));
        ledger.status='prepared';
        write(ledgerFile,ledger);
    catch err
        recordFailure(err);
        rethrow(err);
    end
end

session=ledger.session;
verifyInputs();
assert(isempty(dir(fullfile(session,'attempt_*'))) && isempty(dir(fullfile(session,'checkpoints','*.mat'))) && ...
    ~isfile(fullfile(session,'Agent_Final.mat')) && ~isfile(fullfile(session,'Agent_Success.mat')) && ...
    ~isfile(fullfile(session,'curriculum_state.json')) && ~isfile(fullfile(session,'training_guard_state.json')) && ...
    ~isfile(fullfile(session,'recovery.json')),'FreshSchedule:Fresh','The prepared run must start from episode 0.');
if mode=="prepare"
    fprintf('Fresh schedule prepared. No training started.\n%s\n',session);
    return
end
if cancelled(bundle,session),finishCancelled();return;end
write(fullfile(bundle,'pair_quiescence.json'),assertPairTerminal(root));
write(fullfile(bundle,'capability.json'),trainingtools.preflight_sac_random('gpu',workers));

try
    final=fullfile(session,'Agent_Final.mat');
    for stage=1:numel(quota)
        if cancelled(bundle,session),finishCancelled();return;end
        verifyInputs();
        assert(numel(dir(fullfile(session,'attempt_*')))==stage-1, ...
            'FreshSchedule:Attempts','Unexpected attempt history. Automatic relaunch refused.');
        if stage>1
            previous=ledger.stages{stage-1};
            assert(strcmp(checkpointreview.sha256(final),previous.final_sha256), ...
                'FreshSchedule:Resume','Latest checkpoint no longer matches the previous validated boundary.');
            verifyResumeOrder(session,final);
        end
        ledger.status='training';
        ledger.current_stage=stage;
        write(ledgerFile,ledger);
        info=retry(resume=string(session),maxAttempts=1,start=true);
        started=tic;
        while ~info.supervisor.WaitForExit(1000)
            if toc(started)>=60
                fprintf('Waiting for the bounded Stage %d attempt in %s\n',stage,session);
                started=tic;
            end
        end
        supervisorExit=info.supervisor.ExitCode;
        status=read(fullfile(session,'status.json'));
        if strcmp(status.state,'stopped') && cancelled(bundle,session)
            finishCancelled();return
        end
        assert(supervisorExit==0 && strcmp(status.state,'paused') && status.attempt==stage, ...
            'FreshSchedule:Process','Expected a normal bounded pause. Inspect this attempt.');
        first=limits(stage)-quota(stage);
        evidence=collectStage(session,stage,first,quota(stage),schedule.stages{stage}.id,protocol);
        ledger.stages{stage}=evidence;
        write(ledgerFile,ledger);
        if cancelled(bundle,session),finishCancelled();return;end
        if evidence.guard_paused
            ledger.status='guard_paused';
            write(ledgerFile,ledger);
            fprintf('Guard paused the run at episode %d. No further stages will start.\n',evidence.episode);
            return
        end
        ledger.status='audit';
        write(ledgerFile,ledger);
        audit=trainingtools.audit_sac_scheduled_stage(session,officialFile,stage,final);
        assert(strcmp(checkpointreview.sha256(final),evidence.final_sha256), ...
            'FreshSchedule:Audit','Checkpoint changed during the independent audit.');
        ledger.stages{stage}.audit=audit;
        write(ledgerFile,ledger);
    end
    if cancelled(bundle,session),finishCancelled();return;end
    assert(~isfile(fullfile(session,'Agent_Success.mat')), ...
        'FreshSchedule:Outcome','A scheduled stop must not publish an official success checkpoint.');
    ledger.status='complete';
    ledger.current_stage=0;
    write(ledgerFile,ledger);
    fprintf('Four scheduled stages completed. Original criteria are recorded for each stage.\n%s\n',session);
catch err
    recordFailure(err);
    rethrow(err);
end

    function verifyInputs()
        assertSession(session,runParent);
        assert(isequaln(read(protocolFile),jsondecode(jsonencode(protocol))) && ...
            strcmp(checkpointreview.sha256(officialFile),officialHash) && ...
            strcmp(checkpointreview.sha256(officialSource),officialHash) && ...
            strcmp(checkpointreview.sha256(fullfile(runtime,'training_engine.m')),engineHash) && ...
            strcmp(checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')),protocol.random_path_sha256) && ...
            strcmp(checkpointreview.sha256(scheduleFile),ledger.scheduled_curriculum_sha256) && ...
            strcmp(checkpointreview.sha256(fullfile(session,'curriculum.json')),ledger.scheduled_curriculum_sha256) && ...
            isequaln(read(scheduleFile),jsondecode(jsonencode(schedule))), ...
            'FreshSchedule:Snapshot','The prepared course, protocol or source code changed.');
        cfg=read(fullfile(session,'control.json'));
        [modelFile,manifest]=trainingenv.resolve(session);
        assert(isequaln(manifest,environment) && strcmp(checkpointreview.sha256(modelFile),envHash) && ...
            isequaln(read(fullfile(session,'model.json')),spec) && ...
            isequaln(read(fullfile(session,'training_guard.json')),guard) && ...
            isequaln(read(fullfile(session,'experiment_protocol.json')),jsondecode(jsonencode(runProtocol))) && ...
            strcmp(checkpoint_storage_version(session),'-v7') && ...
            strcmpi(cfg.sessionDir,session) && strcmpi(cfg.modularRoot,root) && ...
            strcmpi(cfg.scriptDir,runtime) && strcmpi(cfg.diagnosticDir,fullfile(session,'diagnostics')) && ...
            strcmp(cfg.executionMode,'parallel') && strcmp(cfg.trainingDevice,'gpu') && ...
            strcmp(cfg.fastRestart,'off') && cfg.numWorkers==workers && cfg.minWorkers==workers && ...
            isempty(cfg.fallbackWorkers) && isempty(cfg.resumeAgentFile) && ...
            cfg.checkpointEvery==interval && cfg.averageWindow==interval && ...
            cfg.episodesPerProcess==max(quota) && cfg.maxAttempts==1 && cfg.maxNoProgressFailures==1, ...
            'FreshSchedule:Configuration','The prepared run configuration changed.');
        for k=1:numel(modelFiles)
            snapshot=fullfile(session,'model_source','+trainingmodels',modelFiles{k});
            assert(strcmp(checkpointreview.sha256(snapshot),modelHashes{k}), ...
                'FreshSchedule:ModelSource','A frozen model file changed: %s',modelFiles{k});
        end
    end

    function finishCancelled()
        ledger.status='cancelled';
        write(ledgerFile,ledger);
        fprintf('Cancellation recorded. No further bounded stage will start.\n');
    end

    function recordFailure(err)
        ledger.status='error';
        ledger.error=struct('identifier',err.identifier,'message',err.message);
        write(ledgerFile,ledger);
    end
end

function evidence=collectStage(session,stage,first,quota,stageId,protocol)
lock=openLock(fullfile(session,'supervisor.lock'),System.IO.FileMode.Open);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
attemptDir=fullfile(session,sprintf('attempt_%05d',stage));
options=read(fullfile(attemptDir,'attempt.json'));
result=read(fullfile(attemptDir,'result.json'));
environment=read(fullfile(attemptDir,'environment_used.json'));
pool=read(fullfile(attemptDir,'pool_ready.json'));
workers=readtable(fullfile(session,'diagnostics','worker_attempts.csv'));
guard=read(fullfile(session,'training_guard_state.json'));
state=read(fullfile(session,'curriculum_state.json'));
final=fullfile(session,'Agent_Final.mat');
archived=fullfile(session,'runs',sprintf('r%06d',stage),'Agent_Final.mat');
[history,last]=checkpoint_resume_state(final);
sha=checkpointreview.sha256(final);
if stage==1
    expectedResume='';
else
    expectedResume=final;
end
assert(height(workers)==stage && workers.Attempt(end)==stage && workers.ExitCode(end)==0 && ...
    workers.ActualWorkers(end)==protocol.workers_requested && pool.actualWorkers==protocol.workers_requested && ...
    strcmp(environment.id,'spatial_v2') && strcmp(environment.model_sha256,protocol.environment_model_sha256) && ...
    strcmp(environment.engine_sha256,protocol.runtime_sha256) && ...
    options.numWorkers==protocol.workers_requested && options.minWorkers==protocol.workers_requested && ...
    strcmp(options.trainingDevice,protocol.device_requested) && strcmp(options.executionMode,protocol.execution_mode) && ...
    strcmp(options.fastRestart,protocol.fast_restart) && options.checkpointEvery==protocol.checkpoint_every && ...
    strcmpi(result.resumeFile,expectedResume) && strcmp(result.finalAgent,final) && ...
    state.stage_index==stage && state.start_episode==first && result.stageIndex==stage && ...
    strcmp(result.stageId,stageId) && numel(state.completed)==stage-1 && ...
    last==result.episodes && last>first && last<=first+quota && ...
    strcmp(checkpointreview.sha256(archived),sha), ...
    'FreshSchedule:Evidence','Unexpected attempt, checkpoint or stage evidence.');
if stage>1
    historyStages=state.completed;
    if iscell(historyStages),historyStages=[historyStages{:}];end
    assert(isequal([historyStages.end_episode],protocol.scheduled_end_episodes(1:stage-1)) && ...
        all(strcmp({historyStages.reason},'episode_budget_reached')), ...
        'FreshSchedule:Boundary','Saved transition history differs from the declared schedule.');
end
if guard.paused
    assert(result.pause && isfield(result,'pauseReason') && strcmp(result.pauseReason,guard.reason), ...
        'FreshSchedule:Guard','Guard state and saved result disagree.');
else
    lastStage=stage==numel(protocol.scheduled_end_episodes);
    expectedDecision='advance';
    if lastStage,expectedDecision='pause';end
    assert(last==first+quota && ~result.success && result.pause==lastStage && ...
        strcmp(result.curriculumDecision,expectedDecision) && strcmp(result.curriculumReason,'episode_budget_reached'), ...
        'FreshSchedule:Boundary','A scheduled stage did not stop at its declared saved boundary.');
end
range=first+1:last;
steps=double(history.EpisodeSteps(range));
rewards=double(history.EpisodeReward(range));
evidence=struct('stage_index',stage,'stage_id',stageId,'first_episode',first+1,'episode',last, ...
    'episode_count',numel(range),'mean_reward',mean(rewards),'mean_steps',mean(steps), ...
    'full_length_count',nnz(steps>=3000),'environment_steps',sum(steps), ...
    'actual_workers',workers.ActualWorkers(end),'duration_seconds',workers.DurationSeconds(end), ...
    'resume_file',result.resumeFile,'guard_paused',guard.paused,'reason',result.curriculumReason, ...
    'final',archived,'final_sha256',sha,'audit',[]);
end

function receipt=assertPairTerminal(root)
pair=fullfile(root,'artifacts','packages','sac-update-frequency-20261121');
reviewFile=fullfile(pair,'review.json');
lockFile=fullfile(pair,'review.lock');
assert(isfile(lockFile) && isfile(reviewFile),'FreshSchedule:PairBusy','The paired trial has no terminal evidence.');
lock=openLock(lockFile,System.IO.FileMode.Open);
release=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledger=read(reviewFile);
comparison=fullfile(pair,'comparison.json');
assert(any(strcmp(ledger.status,{'complete','error','cancelled'})) && ...
    (~strcmp(ledger.status,'complete') || isfile(comparison)), ...
    'FreshSchedule:PairBusy','Wait for the paired trial and its running operations to finish.');
assert(numel(ledger.children)==2 && ~strcmpi(ledger.children(1).session,ledger.children(2).session), ...
    'FreshSchedule:PairBusy','Both paired training sessions must be identifiable before boot.');
pairRuns=fullfile(root,'experiments','sac_random_route_v1','runs');
children=cell(1,2);
for arm=1:2
    session=ledger.children(arm).session;
    assertSession(session,pairRuns);
    childLock=openLock(fullfile(session,'supervisor.lock'),System.IO.FileMode.Open);
    releaseChild=onCleanup(@() childLock.Dispose());
    status=read(fullfile(session,'status.json'));
    assert(any(strcmp(status.state,{'paused','stopped','error','success'})), ...
        'FreshSchedule:PairBusy','A paired training session has not stopped: %s',session);
    children{arm}=struct('session',session,'status',status);
    clear releaseChild
end
receipt=struct('review',reviewFile,'review_sha256',checkpointreview.sha256(reviewFile), ...
    'terminal_status',ledger.status,'comparison_available',isfile(comparison),'children',{children}, ...
    'scope','Recorded prior pilot disposition and released process locks. No pilot checkpoint was used.');
if isfield(ledger,'error'),receipt.error=ledger.error;end
end

function verifyResumeOrder(session,final)
% The existing supervisor orders candidates by last write time.
finalInfo=System.IO.FileInfo(final);
periodic=dir(fullfile(session,'checkpoints','Agent*.mat'));
for k=1:numel(periodic)
    if isempty(regexp(periodic(k).name,'^Agent_?\d+\.mat$','once')),continue;end
    candidate=System.IO.FileInfo(fullfile(periodic(k).folder,periodic(k).name));
    assert(candidate.LastWriteTimeUtc.Ticks<finalInfo.LastWriteTimeUtc.Ticks, ...
        'FreshSchedule:ResumeOrder','The verified final must precede periodic candidates.');
end
end

function assertSession(session,parent)
assert(isfolder(session) && strcmpi(fileparts(session),parent) && ...
    strcmpi(session,char(java.io.File(session).getCanonicalPath())), ...
    'FreshSchedule:Path','The session is outside the dedicated local schedule group.');
end

function stop=cancelled(bundle,session)
stop=isfile(fullfile(bundle,'CANCEL')) || (~isempty(session) && isfile(fullfile(session,'STOP')));
end

function lock=openLock(file,mode)
lock=System.IO.File.Open(file,mode,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
end

function value=read(file)
value=jsondecode(fileread(file));
end

function write(file,value)
trainingcurriculum.write_json(file,value);
end
