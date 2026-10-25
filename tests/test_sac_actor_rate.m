function test_sac_actor_rate()
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
d=load(fullfile(root,'tests','output','sac-replay-resize.mat'),'candidate');original=d.candidate;
before=saveobj(original);agent=trainingtools.set_sac_actor_rate(original,1e-5);
assert(isequaln(saveobj(original),before),'Parent memory changed.');
file=fullfile(root,'tests','output','sac-actor-rate.mat');save(file,'agent','-v7.3');
d=load(file,'agent');agent=d.agent;s=saveobj(agent);
assert(s.ActorOptimizer.LearnRate==1e-5 && agent.AgentOptions.ActorOptimizerOptions.LearnRate==1e-5);
opt=s.ActorOptimizer;opt.LearnRate=before.ActorOptimizer.LearnRate;assert(isequaln(opt,before.ActorOptimizer));
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
env=rlFunctionEnv(obs,act,@step,@reset);
options=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',16,'UseParallel',false, ...
    'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
weights=getLearnableParameters(getActor(agent));train(agent,env,options);
assert(~isequaln(weights,getLearnableParameters(getActor(agent))));
assert(agent.ExperienceBuffer.Length==48);
receipt=jsondecode(fileread(fullfile(root,'tests','output','sac-flight-latest.json')));
source=receipt.sessionDir;parent=fullfile(source,'checkpoints','Agent2.mat');hash=checkpointreview.sha256(parent);
pair=trainingtools.prepare_sac_actor_pair(source,2);
paths={pair.control,pair.candidate};rates=[5e-5 1e-5];
for k=1:2
    cfg=jsondecode(fileread(fullfile(paths{k},'control.json')));
    assert(cfg.maxAttempts==1 && cfg.episodesPerProcess==500 && strcmp(cfg.executionMode,'serial'));
    assert(isfile(fullfile(paths{k},'STOP')) && isempty(dir(fullfile(paths{k},'attempt_*'))));
    rules=jsondecode(fileread(fullfile(paths{k},'training_guard.json')));assert(rules.max_additional_episodes==500);
    d=load(fullfile(paths{k},'checkpoints','Agent2.mat'),'Agent_Stage2');
    spec=jsondecode(fileread(fullfile(paths{k},'model.json')));trainingmodels.validate_agent(d.Agent_Stage2,spec);
    s=saveobj(d.Agent_Stage2);assert(s.ActorOptimizer.LearnRate==rates(k));
end
assert(strcmp(hash,checkpointreview.sha256(parent)));
fprintf('PASS: preserved optimizer state, disk reload,16 synthetic learning steps, two prepared children and unchanged source.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=16;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
