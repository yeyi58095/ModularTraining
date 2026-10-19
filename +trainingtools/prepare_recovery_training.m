function info=prepare_recovery_training(sourceSession,configFile)
% 恢復分支準備：在停止且取得鎖的父 run 上選定 checkpoint，建立獨立的新 run。
% 保留權重與保存歷史，只按配方調整允許設定、保存來源及環境 SHA；不修改父 run 或啟動訓練。
% Fork a stopped curriculum checkpoint; never launch training or mutate parent.
arguments
    sourceSession (1,1) string
    configFile (1,1) string = "configs/recovery_actor_half.json"
end
root=fileparts(fileparts(mfilename('fullpath'))); oldPath=path;
guard=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
sourceSession=absolute(root,sourceSession); configFile=absolute(root,configFile);
settings=jsondecode(fileread(configFile));
continuous=false;
if isfield(settings,'continuous_training')
    validateattributes(settings.continuous_training,{'logical'},{'scalar'});
    continuous=settings.continuous_training;
end
scaleActor=@trainingmodels.scale_std_actor;
if isfield(settings,'exploration_std_scale')
    validateattributes(settings.exploration_std_scale,{'numeric'},{'scalar','positive','<=',1,'finite'});
end
assert(settings.schema_version==1,'Recovery:Schema','Unsupported settings.');
% 指定環境的配方必須配對正確 SLX，避免只更新 JSON 就在舊環境續訓。
if isfield(settings,'expected_runtime_model_sha256') && ~isfile(fullfile(sourceSession,'environment.json'))
    assert(strcmpi(settings.expected_runtime_model_sha256, ...
        checkpointreview.sha256(fullfile(root,'runtime','FAFA_Simulation.slx'))), ...
        'Recovery:EnvironmentMismatch','Runtime model does not match this recovery recipe. Update the complete project before preparing.');
end
validateattributes(settings.checkpoint_episode,{'numeric'},{'scalar','integer','positive'});
validateattributes(settings.actor_learning_rate_scale,{'numeric'},{'scalar','positive','<=',1,'finite'});
validateattributes(settings.episodes_per_process,{'numeric'},{'scalar','integer','positive'});
if continuous
    assert(settings.max_additional_episodes==0,'Recovery:Budget','Continuous mode requires max_additional_episodes=0 (unbounded).');
else
    validateattributes(settings.max_additional_episodes,{'numeric'},{'scalar','integer','positive','finite'});
end
trainingguard.assess([],[],0,settings.guard);
assert(mod(settings.max_additional_episodes,settings.episodes_per_process)==0, ...
    'Recovery:Budget','Budget must contain whole segments.');
assert(settings.episodes_per_process==settings.guard.window, ...
    'Recovery:Window','Use one guard window per process for this recovery recipe.');
% 父 run 必須停止且取得鎖，避免複製正在保存或被另一程序更新的模型。
lock=System.IO.File.Open(char(fullfile(sourceSession,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sourceSession,'status.json')));
assert(any(strcmp(status.state,{'stopped','paused','success','error'})), ...
    'Recovery:Active','Parent must be stopped.');
checkpoint=fullfile(sourceSession,'checkpoints',sprintf('Agent%d.mat',settings.checkpoint_episode));
checkpoint_select_agent(checkpoint);
[history,episode]=checkpoint_resume_state(checkpoint);
assert(episode==settings.checkpoint_episode,'Recovery:Episode','History/episode mismatch.');
parentHash=checkpointreview.sha256(checkpoint);
spec=jsondecode(fileread(fullfile(sourceSession,'model.json')));
cfg=jsondecode(fileread(fullfile(sourceSession,'control.json')));
plan=trainingcurriculum.load_plan(fullfile(sourceSession,'curriculum.json'),true);
assert(strcmp(plan.model,spec.name),'Recovery:Model','Parent model and curriculum differ.');
state=jsondecode(fileread(fullfile(sourceSession,'curriculum_state.json')));
completed=state.completed; if ~iscell(completed), completed=num2cell(completed); end
assert(numel(completed)==state.stage_index-1,'Recovery:State','Incomplete stage history.');
% Reconstruct only from recorded transitions, not reward or filename guesses.
% 只能用已記錄 stage 轉換重建分支起點，不能用 reward 或檔名猜階段。
boundary=0;
for i=1:numel(completed)
    item=completed{i};
    assert(strcmp(item.id,plan.stages{i}.id) && item.start_episode==boundary && ...
        item.end_episode>boundary,'Recovery:State','Invalid recorded stage boundary.');
    boundary=item.end_episode;
end
assert(boundary==state.start_episode,'Recovery:State','Invalid current boundary.');
stage=1; startEpisode=0;
while stage<=numel(completed) && episode>completed{stage}.end_episode
    startEpisode=completed{stage}.end_episode; stage=stage+1;
end
forkState=struct('stage_index',stage,'start_episode',startEpisode, ...
    'completed',{completed(1:stage-1)});
entries=whos('-file',checkpoint); name='saved_agent';
if ~any(strcmp({entries.name},name)), name='Agent_Stage2'; end
data=load(checkpoint,name); agent=data.(name);
addpath(fullfile(sourceSession,'model_source'),'-begin');
trainingmodels.validate_agent(agent,spec);
if isfield(settings,'expected_actor_learning_rate')
    assert(spec.actorLearnRate==settings.expected_actor_learning_rate, ...
        'Recovery:SourceRate','Unexpected source learning rate. Select the intended recovery parent.');
end
actorBefore=getLearnableParameters(getActor(agent)); criticBefore=getLearnableParameters(getCritic(agent));
% 同步調整 model spec 與 agent optimizer；前後核對 actor／critic 權重不變。
oldRate=spec.actorLearnRate; spec.actorLearnRate=oldRate*settings.actor_learning_rate_scale;
agent.AgentOptions.ActorOptimizerOptions.LearnRate=spec.actorLearnRate;
if isfield(settings,'exploration_std_scale')
    assert(~isfield(spec,'explorationStdScale'),'Recovery:StdLayout','Already scaled parent; do not scale again.');
    agent=setActor(agent,scaleActor(getActor(agent),settings.exploration_std_scale));
    spec.explorationStdScale=settings.exploration_std_scale;
end
trainingmodels.validate_agent(agent,spec);
assert(isequaln(actorBefore,getLearnableParameters(getActor(agent))) && ...
    isequaln(criticBefore,getLearnableParameters(getCritic(agent))), ...
    'Recovery:Weights','Optimizer change altered weights.');
group=plan.model; if isfield(cfg,'curriculumName'), group=cfg.curriculumName; end
assert(~isempty(regexp(group,'^[A-Za-z0-9_-]+$','once')),'Recovery:Group','Invalid group name.');
base=fullfile(root,'experiments',group,'runs'); if ~isfolder(base), mkdir(base); end
[~,tag]=fileparts(tempname(base));
folder=fullfile(base,[char(datetime('now','Format','yyyyMMdd_HHmmss')) '_recovery_' tag(1:10)]);
% 先在 .preparing 暫存目錄完成保存與驗證，未完整發布者 retry 拒絕接續。
staging=[folder '.preparing']; mkdir(staging);
if isfile(fullfile(sourceSession,'environment.json')) || isfolder(fullfile(sourceSession,'environment'))
    [parentEnvironment,parentManifest]=trainingenv.resolve(sourceSession);
    if isfield(settings,'expected_runtime_model_sha256')
        assert(strcmpi(settings.expected_runtime_model_sha256,checkpointreview.sha256(parentEnvironment)), ...
            'Recovery:EnvironmentMismatch','Recipe requests a different environment. Bound recovery currently inherits its parent environment.');
    end
    trainingenv.snapshot(fullfile(sourceSession,'environment.json'),fileparts(parentEnvironment),staging);
else
    assert(~isfield(plan,'environment'),'Environment:Unbound','Version 2 parent is missing its environment snapshot.');
    trainingenv.capture_runtime(fullfile(root,'runtime'),staging);
end
[childEnvironment,childManifest]=trainingenv.resolve(staging);
cfg.environmentId=childManifest.id;
% On failure retain only a clearly labelled preparation directory; no launcher
% accepts it until recovery.json is published complete.
if continuous
    for k=1:numel(plan.stages),plan.stages{k}.on_limit='continue';end
end
trainingcurriculum.snapshot(plan,fullfile(sourceSession,'curriculum.json'),staging);
copyfile(fullfile(sourceSession,'model_source'),fullfile(staging,'model_source'));
if isfield(settings,'exploration_std_scale')
    % The child explicitly snapshots support for its changed actor layout.
    for file=["build_agent.m","validate_agent.m","scale_std_actor.m"]
        copyfile(fullfile(root,'+trainingmodels',file), ...
            fullfile(staging,'model_source','+trainingmodels',file));
    end
end
trainingcurriculum.write_json(fullfile(staging,'model.json'),spec);
trainingcurriculum.write_json(fullfile(staging,'curriculum_state.json'),forkState);
mkdir(fullfile(staging,'checkpoints'));
target=fullfile(staging,'checkpoints',sprintf('Agent%d.mat',episode));
checkpoint_save_final(target,agent,history);
checkpoint_select_agent(target);
cfg.sessionDir=folder; cfg.scriptDir=fullfile(root,'runtime'); cfg.modularRoot=root;
cfg.diagnosticDir=fullfile(folder,'diagnostics'); cfg.matlabExe=fullfile(matlabroot,'bin','matlab.exe');
cfg.resumeAgentFile=''; cfg.curriculumEnabled=true; cfg.curriculumName=group;
cfg.episodesPerProcess=settings.episodes_per_process;
cfg.checkpointEvery=min(cfg.checkpointEvery,cfg.episodesPerProcess);
cfg.averageWindow=min(cfg.averageWindow,cfg.episodesPerProcess);
cfg.maxAttempts=0;
trainingcurriculum.write_json(fullfile(staging,'control.json'),cfg);
rules=settings.guard; rules.origin_episode=episode;
rules.max_additional_episodes=settings.max_additional_episodes;
if continuous
    rules.budget_enabled=false;
    rules.regression_action='monitor';
end
trainingcurriculum.write_json(fullfile(staging,'training_guard.json'),rules);
lineage=struct('schema_version',1,'status','prepared','parent_session',char(sourceSession), ...
    'parent_checkpoint',char(checkpoint),'parent_sha256',parentHash,'parent_episode',episode, ...
    'actor_learning_rate_before',oldRate,'actor_learning_rate_after',spec.actorLearnRate, ...
    'weights_preserved',true,'settings',settings, ...
    'selection','User-selected candidate; not automatic evaluation-best selection');
lineage.parent_curriculum_sha256=checkpointreview.sha256(fullfile(sourceSession,'curriculum.json'));
lineage.parent_model_sha256=checkpointreview.sha256(fullfile(sourceSession,'model.json'));
lineage.child_checkpoint_sha256=checkpointreview.sha256(target);
% These identify the local environment at preparation, not historical parent execution.
% 環境指紋表示本機準備當下版本，不證明父 run 歷史執行過相同版本。
lineage.prepared_runtime_model_sha256=checkpointreview.sha256(childEnvironment);
lineage.environment_id=childManifest.id;
lineage.prepared_runtime_engine_sha256=checkpointreview.sha256(fullfile(root,'runtime','training_engine.m'));
trainingcurriculum.write_json(fullfile(staging,'recovery.json'),lineage);
trainingcurriculum.write_json(fullfile(staging,'status.json'), ...
    struct('state','paused','attempt',0,'message','Recovery prepared; no training started.'));
fid=fopen(fullfile(staging,'supervisor.lock'),'w'); assert(fid~=-1); fclose(fid);
fid=fopen(fullfile(staging,'STOP'),'w'); assert(fid~=-1); fclose(fid);
assert(strcmp(parentHash,checkpointreview.sha256(checkpoint)),'Recovery:SourceChanged','Parent changed.');
movefile(staging,folder);
info=struct('sessionDir',folder,'parentEpisode',episode,'stageIndex',stage, ...
    'actorLearnRate',spec.actorLearnRate,'maxAdditionalEpisodes',settings.max_additional_episodes, ...
    'continuousTraining',continuous);
disp(info); fprintf('Prepared only. Start explicitly with retry(resume=info.sessionDir).\n');
end
function value=absolute(root,value)
% 將相對輸入接到 root，回傳規範化絕對路徑以供跨目錄呼叫。
if ~java.io.File(char(value)).isAbsolute(), value=fullfile(root,value); end
value=char(java.io.File(char(value)).getCanonicalPath());
end
