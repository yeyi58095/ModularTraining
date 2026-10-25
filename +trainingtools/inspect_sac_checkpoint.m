function report=inspect_sac_checkpoint(sessionDir,episode)
% Read-only R2024b SAC snapshot audit. No train/sim or agent option setters.
arguments
    sessionDir (1,1) string
    episode (1,1) double {mustBeInteger,mustBePositive}
end
assert(strcmp(version('-release'),'2024b'),'SAC:Release','Requires R2024b.');
root=fileparts(fileparts(mfilename('fullpath')));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
sessionDir=string(char(java.io.File(char(sessionDir)).getCanonicalPath()));
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
guard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(strcmp(status.state,'paused'),'SAC:Active','Run must be paused.');
file=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',episode));
fingerprint=checkpointreview.sha256(file);
vars=whos('-file',file);name='saved_agent';
if ~any(strcmp({vars.name},name)),name='Agent_Stage2';end
assert(any(strcmp({vars.name},name)),'SAC:Variable','No supported agent variable.');
data=load(file,name);agent=data.(name);clear data
assert(isa(agent,'rl.agent.rlSACAgent'),'SAC:Type','Requires SAC checkpoint.');
s=saveobj(agent);
report=struct('schema_version',1,'status','complete','source',char(file), ...
    'sha256',fingerprint,'episode',episode,'matlab_release',version('-release'), ...
    'scope','Stored checkpoint state only; no loss history or causal diagnosis.');
report.saved_fields=fieldnames(s);
report.policy_state_saved=isfield(s,'PolicyState') && isfield(s.PolicyState,'EntropyWeight');
report.current_entropy_weight=double(gather(getEntropyWeight(agent)));
o=agent.AgentOptions;
report.options=struct('discount',o.DiscountFactor,'batch_size',o.MiniBatchSize, ...
    'sequence_length',o.SequenceLength,'learning_frequency',o.LearningFrequency, ...
    'actor_lr',o.ActorOptimizerOptions.LearnRate, ...
    'critic_lr',[o.CriticOptimizerOptions.LearnRate], ...
    'entropy_lr',[o.EntropyWeightOptions.LearnRate], ...
    'target_entropy',[o.EntropyWeightOptions.TargetEntropy]);
report.networks=struct;
for f={'Actor','Critic','TargetCritic'}
    key=f{1};
    if ~isfield(s,key),continue;end
    nets=s.(key);summaries=cell(1,numel(nets));
    for k=1:numel(nets)
        summaries{k}=parameterStats(getLearnableParameters(nets(k)));
    end
    report.networks.(key)=summaries;
end
report.critic_target_gap=cell(1,numel(s.Critic));
if isfield(s,'TargetCritic')
    for k=1:numel(s.Critic)
        x=getLearnableParameters(s.Critic(k));y=getLearnableParameters(s.TargetCritic(k));
        delta=cellfun(@minus,x,y,'UniformOutput',false);
        report.critic_target_gap{k}=parameterStats(delta);
    end
end
report.optimizer_saved=struct('actor',isfield(s,'ActorOptimizer'), ...
    'critic',isfield(s,'CriticOptimizer'),'entropy',isfield(s,'EntropyOptimizer'));
report.replay=struct('saved',isfield(s,'ExperienceBuffer'));
if report.replay.saved
    b=s.ExperienceBuffer;
    report.replay.capacity=b.MaxLength;report.replay.length=b.Length;
    n=min(10000,b.Length);
    report.replay.sample_scope='Most recent at most10000 chronological transitions; not full-buffer distribution.';
    report.replay.sample_count=n;
    if n>0
        e=getLastNData(b,n);
        r=double([e.Reward]);done=double([e.IsDone]);
        report.replay.reward_mean=mean(r);report.replay.reward_min=min(r);
        report.replay.reward_max=max(r);report.replay.reward_nonfinite=sum(~isfinite(r));
        report.replay.terminal_count=sum(done~=0);
    end
end
clear agent s b e
assert(strcmp(fingerprint,checkpointreview.sha256(file)),'SAC:Changed','Source checkpoint changed.');
report.source_unchanged=true;
fprintf('Episode%d | alpha=%s | policy state saved=%d\n',episode, ...
    mat2str(report.current_entropy_weight,6),report.policy_state_saved);
end

function out=parameterStats(p)
count=0;bad=0;sq=0;peak=0;
for k=1:numel(p)
    x=p{k};if isa(x,'dlarray'),x=extractdata(x);end
    x=double(gather(x));count=count+numel(x);bad=bad+sum(~isfinite(x(:)));
    finite=x(isfinite(x));sq=sq+sum(finite.^2);peak=max([peak;abs(finite(:))]);
end
out=struct('count',count,'nonfinite',bad,'finite_l2',sqrt(sq),'finite_max_abs',peak);
end
