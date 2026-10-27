function test_sac_critic_rate()
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
d=load(fullfile(root,'tests','output','sac-actor-rate.mat'),'agent');original=d.agent;
before=saveobj(original);agent=trainingtools.set_sac_critic_rate(original,2e-5);
assert(isequaln(saveobj(original),before));
file=string(tempname(fullfile(root,'tests','output')))+".mat";save(file,'agent','-v7');
d=load(file,'agent');agent=d.agent;s=saveobj(agent);
for k=1:2
    assert(s.CriticOptimizer(k).LearnRate==2e-5);
    c=s.CriticOptimizer(k);c.LearnRate=before.CriticOptimizer(k).LearnRate;
    assert(isequaln(c,before.CriticOptimizer(k)));
end
env=rlFunctionEnv(rlNumericSpec([10 1]), ...
    rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1),@step,@reset);
opts=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',16,'UseParallel',false, ...
    'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
critics=getCritic(agent);weights=getLearnableParameters(critics(1));
train(agent,env,opts);critics=getCritic(agent);
assert(~isequaln(weights,getLearnableParameters(critics(1))));
source=fullfile(root,'experiments','curriculum','runs','20261027_014332_recovery_tp16e71293');
hash=checkpointreview.sha256(fullfile(source,'checkpoints','Agent2.mat'));
recipe=jsondecode(fileread(fullfile(root,'configs','sac_mlp_2100_critic_slow.json')));
recipe.checkpoint_episode=2;cfg=string(tempname(fullfile(root,'tests','output')))+".json";
trainingcurriculum.write_json(cfg,recipe);
info=trainingtools.prepare_recovery_training(source,cfg);
spec=jsondecode(fileread(fullfile(info.sessionDir,'model.json')));
assert(abs(spec.criticLearnRate-2e-5)<1e-15 && spec.actorLearnRate==1e-5);
assert(strcmp(hash,checkpointreview.sha256(fullfile(source,'checkpoints','Agent2.mat'))));
assert(isempty(dir(fullfile(info.sessionDir,'attempt_*'))) && isfile(fullfile(info.sessionDir,'STOP')));
assert(strcmp(checkpoint_storage_version(info.sessionDir),'-v7'));
fprintf('PASS: critic optimizer preservation, v7 reload,16 synthetic updates, MLP child preparation; source unchanged.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=16;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
