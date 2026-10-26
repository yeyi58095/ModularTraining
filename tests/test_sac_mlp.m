function test_sac_mlp()
% Bounded synthetic learning and preparation; no production run launched.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
spec=trainingmodels.load_profile('sac_mlp128');
agent=trainingmodels.build_agent(spec,obs,act,'cpu');trainingmodels.validate_agent(agent,spec);
bad=spec;bad.hiddenUnits=64;failed=false;
try,trainingmodels.validate_agent(agent,bad);catch ex,failed=strcmp(ex.identifier,'Modular:ArchitectureMismatch');end
assert(failed);
recurrent=trainingmodels.load_profile('sac_lstm128');
old=trainingmodels.build_agent(recurrent,obs,act,'cpu');trainingmodels.validate_agent(old,recurrent);clear old
spec.numWarmStartSteps=8;spec.miniBatchSize=4;spec.learningFrequency=8;
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
env=rlFunctionEnv(obs,act,@step,@reset);
opts=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',32,'UseParallel',false, ...
    'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
weights=getLearnableParameters(getActor(agent));train(agent,env,opts);
assert(~isequaln(weights,getLearnableParameters(getActor(agent))));
file=fullfile(root,'tests','output','sac-mlp.mat');save(file,'agent','-v7.3');
d=load(file,'agent');trainingmodels.validate_agent(d.agent,spec);
x=saveobj(agent);y=saveobj(d.agent);
for name={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(x.(name{1}),y.(name{1})));
end
train(d.agent,env,opts);assert(d.agent.ExperienceBuffer.Length==64);
info=trainingtools.prepare_sac_mlp_trial();
c=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
p=trainingcurriculum.load_plan(fullfile(info.sessionDir,'curriculum.json'),true);
assert(c.maxAttempts==1 && c.episodesPerProcess==500 && strcmp(c.executionMode,'serial'));
assert(numel(p.stages)==1 && p.stages{1}.max_episodes==2000 && strcmp(p.model,'sac_mlp128'));
assert(isempty(dir(fullfile(info.sessionDir,'attempt_*'))) && ~isfile(fullfile(info.sessionDir,'recovery.json')));
fprintf('PASS: MLP architecture, recurrent regression,64 synthetic steps, serialized states, fresh bounded preparation.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=32;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
