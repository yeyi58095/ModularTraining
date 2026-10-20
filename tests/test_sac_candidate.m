function test_sac_candidate()
% Bounded CPU synthetic training, save/load and second train call. Not flight convergence.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
rng(20261020);
obs=rlNumericSpec([10 1]);obs.Name='observation';
act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
spec=trainingmodels.load_profile('sac_lstm128');
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
trainingmodels.validate_agent(agent,spec);
wrong=spec;wrong.lstmUnits=64;rejected=false;
try,trainingmodels.validate_agent(agent,wrong);catch,rejected=true;end
assert(rejected);
% Same implementation with a smaller warmup/batch for a bounded learning test.
spec.numWarmStartSteps=32;spec.miniBatchSize=8;spec.sequenceLength=8;spec.learningFrequency=8;
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
env=rlFunctionEnv(obs,act,@step,@reset);
before=getLearnableParameters(getActor(agent));
options=rlTrainingOptions('MaxEpisodes',2,'MaxStepsPerEpisode',64, ...
    'UseParallel',false,'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',2);
history=train(agent,env,options);
assert(numel(history.EpisodeReward)==2);
assert(~isequaln(before,getLearnableParameters(getActor(agent))),'Test:NoLearning','SAC actor did not update.');
out=fullfile(root,'tests','output');if ~isfolder(out),mkdir(out);end
file=fullfile(out,'sac-smoke.mat');
checkpoint_save_final(file,agent,history);
assert(strcmp(checkpoint_select_agent(file),file));
saved=load(file,'Agent_Stage2');restored=saved.Agent_Stage2;
trainingmodels.validate_agent(restored,spec);
assert(isequaln(getLearnableParameters(getActor(agent)),getLearnableParameters(getActor(restored))));
assert(restored.ExperienceBuffer.Length==agent.ExperienceBuffer.Length && restored.ExperienceBuffer.Length>0);
count=restored.ExperienceBuffer.Length;
train(restored,env,options);
assert(restored.ExperienceBuffer.Length>count,'Test:ReplayReset','Replay was reset on second train.');
fprintf('PASS: recurrent SAC twin critics, action, real updates, save/load and replay retained across train calls.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=64;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
