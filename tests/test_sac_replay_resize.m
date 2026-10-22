function test_sac_replay_resize()
% Bounded synthetic learning; checks state retention and continued learning.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
rng(20261022);
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
spec=trainingmodels.load_profile('sac_lstm128');spec.lstmUnits=16;
spec.experienceBufferLength=128;spec.miniBatchSize=4;spec.sequenceLength=4;
spec.numWarmStartSteps=8;spec.learningFrequency=8;
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
env=rlFunctionEnv(obs,act,@step,@reset);
opts=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',32,'UseParallel',false, ...
    'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
train(agent,env,opts);
original=allExperiences(agent.ExperienceBuffer);
base=trainingtools.resize_sac_replay(agent,128);
candidate=trainingtools.resize_sac_replay(agent,640);
assert(agent.ExperienceBuffer.MaxLength==128 && base.ExperienceBuffer.MaxLength==128);
assert(isequaln(original,allExperiences(candidate.ExperienceBuffer)));
spec.experienceBufferLength=640;trainingmodels.validate_agent(candidate,spec);
out=fullfile(root,'tests','output');if ~isfolder(out),mkdir(out);end
beforeSave=saveobj(candidate);
file=fullfile(out,'sac-replay-resize.mat');save(file,'candidate','-v7.3');
s=load(file,'candidate');candidate=s.candidate;
afterLoad=saveobj(candidate);
for field={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(beforeSave.(field{1}),afterLoad.(field{1})));
end
assert(candidate.ExperienceBuffer.MaxLength==640 && candidate.ExperienceBuffer.Length==32);
before=getLearnableParameters(getActor(candidate));train(candidate,env,opts);
assert(candidate.ExperienceBuffer.Length==64);
assert(~isequaln(before,getLearnableParameters(getActor(candidate))));
assert(agent.ExperienceBuffer.Length==32 && isequaln(original,allExperiences(agent.ExperienceBuffer)));
fprintf('PASS: replay grow, original isolation, serialized state retention, disk reload, further learning.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=32;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
