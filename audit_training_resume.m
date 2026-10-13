function report=audit_training_resume(sessionDir,opt)
% 續訓稽核：比對停止 run 的 checkpoint 與 Agent_Initial 來源、設定及 actor／critic 權重。
% 回傳並保存稽核報告；不解析 optimizer 私有狀態，不模擬、訓練或覆寫 agent。
% Read stopped-session agents and initial snapshots; never train or simulate.
arguments
    sessionDir (1,1) string
    opt.episodes (1,:) double {mustBeInteger,mustBePositive} = [10600 10700 11000]
end
root=fileparts(mfilename('fullpath')); previous=path;
cleanup=onCleanup(@()path(previous)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
if ~java.io.File(char(sessionDir)).isAbsolute(), sessionDir=fullfile(root,sessionDir); end
sessionDir=string(char(java.io.File(char(sessionDir)).getCanonicalPath()));
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@()lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(any(strcmp(status.state,{'paused','stopped','success','error'})), ...
    'Audit:Active','Stop training before auditing.');
assert(~isempty(opt.episodes),'Audit:Empty','Select at least one checkpoint.');
report=struct('schema_version',1,'scope', ...
    'Read-only parameter audit; differences do not prove the cause of regression. Optimizer internal state is not inspected.', ...
    'checkpoints',{{}},'initial_snapshots',{{}});
base=[];
for ep=opt.episodes
    file=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep));
    [~,actual]=checkpoint_resume_state(file);
    assert(actual==ep,'Audit:Episode','Checkpoint history mismatch.');
    agent=readAgent(file);
    if isempty(base), base=agent; end
    row=describe(agent); row.episode=ep;
    row.actor_vs_first=distance(getActor(base),getActor(agent));
    row.critic_vs_first=distance(getCritic(base),getCritic(agent));
    report.checkpoints{end+1}=row;
end
files=dir(fullfile(sessionDir,'runs','r*','Agent_Initial.mat'));
for i=1:numel(files)
    folder=files(i).folder; optionsFile=fullfile(folder,'TrainingOptions.mat');
    if ~isfile(optionsFile), continue; end
    options=load(optionsFile,'resumeAgentFile','numWorkers','optionsForDisk');
    source=string(options.resumeAgentFile);
    [~,name,ext]=fileparts(source);
    % Resolve moved-session checkpoints locally; never load stale absolute paths.
    source=fullfile(sessionDir,'checkpoints',name+ext);
    if ~isfile(source), continue; end
    [~,ep]=checkpoint_resume_state(source);
    if ~ismember(ep,opt.episodes), continue; end
    initial=readAgent(fullfile(folder,'Agent_Initial.mat')); resumed=readAgent(source);
    row=describe(initial); [~,row.run]=fileparts(folder); row.resume_episode=ep;
    row.workers=options.numWorkers;
    row.worker_seeds=options.optionsForDisk.ParallelizationOptions.WorkerRandomSeeds;
    row.actor_vs_resume=distance(getActor(resumed),getActor(initial));
    row.critic_vs_resume=distance(getCritic(resumed),getCritic(initial));
    row.options_equal=isequaln(describe(resumed),describe(initial));
    report.initial_snapshots{end+1}=row;
end
report.initial_snapshot_count=numel(report.initial_snapshots);
out=fullfile(sessionDir,'reports'); if ~isfolder(out), mkdir(out); end
[~,tag]=fileparts(tempname);
file=fullfile(out,['resume_audit_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '_' tag '.json']);
trainingcurriculum.write_json(file,report);
fprintf('Audit complete. No training or simulation. Report: %s\n',file);
end
function agent=readAgent(file)
% 按 saved_agent／Agent_Stage2 變數名稱讀取 agent；主要 checkpoint 相容性由呼叫端先檢查。
entries=whos('-file',file); name='saved_agent';
if ~any(strcmp({entries.name},name)), name='Agent_Stage2'; end
data=load(file,name); agent=data.(name);
end
function row=describe(agent)
% 擷取 optimizer、PPO、sample time 與探索模式等設定，供稽核比較。
o=agent.AgentOptions;
row=struct('actor_learn_rate',o.ActorOptimizerOptions.LearnRate, ...
    'critic_learn_rate',o.CriticOptimizerOptions.LearnRate, ...
    'actor_gradient_threshold',o.ActorOptimizerOptions.GradientThreshold, ...
    'critic_gradient_threshold',o.CriticOptimizerOptions.GradientThreshold, ...
    'clip_factor',o.ClipFactor,'entropy_weight',o.EntropyLossWeight, ...
    'epochs',o.NumEpoch,'horizon',o.ExperienceHorizon,'minibatch',o.MiniBatchSize, ...
    'sample_time',o.SampleTime,'discount',o.DiscountFactor, ...
    'use_exploration',agent.UseExplorationPolicy);
end
function result=distance(a,b)
% 逐一比較兩組參數的形狀與數值，回傳相等性及差異統計。
x=getLearnableParameters(a); y=getLearnableParameters(b);
assert(numel(x)==numel(y),'Audit:Shape','Parameter layout differs.');
total=0; baseline=0; peak=0; equal=true; finite=true;
for k=1:numel(x)
    u=x{k}; v=y{k};
    if isa(u,'dlarray'), u=extractdata(u); end
    if isa(v,'dlarray'), v=extractdata(v); end
    u=double(gather(u)); v=double(gather(v));
    assert(isequal(size(u),size(v)),'Audit:Shape','Parameter shape differs.');
    equal=equal && isequaln(u,v); finite=finite && all(isfinite(u(:))) && all(isfinite(v(:)));
    delta=v-u; total=total+sum(delta(:).^2); baseline=baseline+sum(u(:).^2);
    peak=max(peak,max(abs(delta(:))));
end
result=struct('exact_equal',equal,'all_finite',finite,'l2_change',sqrt(total), ...
    'relative_l2_change',sqrt(total)/max(sqrt(baseline),eps),'max_abs_change',peak);
end
