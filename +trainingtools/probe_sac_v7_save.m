function out=probe_sac_v7_save(source,episode)
% Isolated diagnostic only: no training, publication, or source mutation.
arguments
    source (1,1) string
    episode (1,1) double {mustBeInteger,mustBePositive}
end
root=fileparts(fileparts(mfilename('fullpath')));
assert(java.io.File(char(source)).isAbsolute(),'Use an absolute source path.');
lock=System.IO.File.Open(char(fullfile(source,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(source,'status.json')));
assert(strcmp(status.state,'paused'),'Source must be paused.');
out=string(tempname(fullfile(root,'artifacts')));mkdir(out);
diary(char(fullfile(out,'probe.log')));diary on;
diaryGuard=onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('Diagnostic folder: %s\n',out);
file=fullfile(source,'checkpoints',sprintf('Agent%d.mat',episode));
hash=checkpointreview.sha256(file);
fprintf('STEP 1: loading source (no simulation).\n');drawnow;
d=load(file);name='Agent_Stage2';
if isfield(d,'saved_agent'),name='saved_agent';end
assert(isfield(d,name),'Agent missing.');
assert(isa(d.(name),'rl.agent.rlSACAgent'),'SAC only.');
fprintf('STEP 2: preserve state while changing actor rate to 1e-5.\n');drawnow;
d.(name)=trainingtools.set_sac_actor_rate(d.(name),1e-5);
before=saveobj(d.(name));
target=fullfile(out,'probe-v7.mat');
fprintf('STEP 3: save independent v7 file. Not a resumable run.\n');drawnow;
save(target,'-struct','d','-v7');
names=fieldnames(d);entries=whos('-file',target);
assert(isequal(sort(names),sort({entries.name}')),'Save omitted variables.');
fprintf('STEP 4: reload and verify saved state.\n');drawnow;
loaded=load(target);after=saveobj(loaded.(name));
for key={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState','AgentOptions'}
    assert(isequaln(before.(key{1}),after.(key{1})),'State changed: %s',key{1});
end
for key={'Actor','Critic','TargetCritic'}
    a=before.(key{1});b=after.(key{1});assert(numel(a)==numel(b));
    for k=1:numel(a)
        assert(isequaln(getLearnableParameters(a(k)),getLearnableParameters(b(k))));
    end
end
[a,ids]=getLastNData(before.ExperienceBuffer,before.ExperienceBuffer.Length);
[b,newIds]=getLastNData(after.ExperienceBuffer,after.ExperienceBuffer.Length);
assert(isequaln(a,b) && isequaln(ids,newIds),'Replay changed.');
for k=1:numel(names)
    if strcmp(names{k},name),continue;end
    x=d.(names{k});y=loaded.(names{k});
    if isa(x,'rl.train.result.rlTrainingResult') || isa(x,'rl.train.rlTrainingResult')
        assert(strcmp(class(x),class(y)));
        for key={'TimeStamp','EpisodeIndex','EpisodeReward','EpisodeSteps', ...
                'EpisodeQ0','EvaluationStatistic','ActorGradientSteps','CriticGradientSteps'}
            if isprop(x,key{1})
                assert(isequaln(x.(key{1}),y.(key{1})),'History statistic changed: %s',key{1});
            end
        end
    else
        assert(isequaln(x,y),'Other variable changed: %s',names{k});
    end
end
assert(strcmp(hash,checkpointreview.sha256(file)),'Source changed.');
report=struct('status','passed','source',char(file),'source_sha256',hash, ...
    'matlab_version',version,'format','v7','actor_rate',1e-5, ...
    'source_unchanged',true,'optimizer_replay_weights_history_statistics_verified',true, ...
    'scope','Isolated same-process save/reload only; no training or recovery publication.');
trainingcurriculum.write_json(fullfile(out,'report.json'),report);
fprintf('PASS. Share probe.log and report.json; do not retry this artifact folder.\n');
end
