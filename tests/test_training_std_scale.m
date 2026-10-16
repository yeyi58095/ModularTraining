function test_training_std_scale()
% Isolated preparation plus synthetic CPU PPO update; no flight training.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','recovery-smoke-latest.json')));
source=receipt.sessionDir;
recipe=jsondecode(fileread(fullfile(root,'configs','recovery_v2_18000_std_half.json')));
recipe=rmfield(recipe,'expected_runtime_model_sha256');recipe.checkpoint_episode=2;
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);
recipeFile=fullfile(fixture,'recipe.json');trainingcurriculum.write_json(recipeFile,recipe);
src=fullfile(source,'checkpoints','Agent2.mat');hash=checkpointreview.sha256(src);
child=prepare_recovery_training(source,recipeFile);
spec=jsondecode(fileread(fullfile(child.sessionDir,'model.json')));
x=load(src); original=x.Agent_Stage2;
y=load(fullfile(child.sessionDir,'checkpoints','Agent2.mat'));agent=y.Agent_Stage2;
addpath(root,'-begin');trainingmodels.validate_agent(agent,spec);
a=getActor(original);a.UseDevice='cpu';b=getActor(agent);b.UseDevice='cpu';
state=a.State;for j=1:numel(state),state{j}=state{j}*0;end;a.State=state;b.State=state;
rng(42);
for j=1:150
 obs=randn(10,1)*.1;
 [pa,sa]=evaluate(a,{obs});[pb,sb]=evaluate(b,{obs});
 assert(abs(double(pa{1})-double(pb{1}))<1e-6 && abs(.5*double(pa{2})-double(pb{2}))<1e-6);
 a.State=cellfun(@dlarray,sa,'UniformOutput',false);b.State=cellfun(@dlarray,sb,'UniformOutput',false);
end
assert(isequaln(getLearnableParameters(getActor(original)),getLearnableParameters(getActor(agent))));
try,trainingmodels.scale_std_actor(b,.5);error('Test:Missing','Expected rejection');catch e,assert(strcmp(e.identifier,'Recovery:StdLayout'));end
bad=spec;bad.explorationStdScale=.25;
try,trainingmodels.validate_agent(agent,bad);error('Test:Missing','Expected rejection');catch e,assert(strcmp(e.identifier,'Modular:StdScale'));end
% Exercise the child's actual snapshot through the normal training adapter.
cfg=jsondecode(fileread(fullfile(child.sessionDir,'control.json')));overrides=training(cfg,struct());
overrides.agentValidator(agent);
built=overrides.agentFactory(getObservationInfo(agent),getActionInfo(agent),'cpu');
overrides.agentValidator(built);
% Test-only optimizer settings and toy dynamics; no changes to saved run.
lab=load(fullfile(root,'diagnostic_packages','recovery_review_20261016','checkpoints','Agent18000.mat'));
if isfield(lab,'saved_agent'),agent=lab.saved_agent;else,agent=lab.Agent_Stage2;end
addpath(root,'-begin');
agent=setActor(agent,trainingmodels.scale_std_actor(getActor(agent),.5));
actor=getActor(agent);actor.UseDevice='cpu';agent=setActor(agent,actor);
critic=getCritic(agent);critic.UseDevice='cpu';agent=setCritic(agent,critic);
agent.AgentOptions.ExperienceHorizon=512;agent.AgentOptions.MiniBatchSize=128;agent.AgentOptions.NumEpoch=3;
agent.AgentOptions.LearningFrequency=512; % toy test must actually trigger an update
env=rlFunctionEnv(getObservationInfo(agent),getActionInfo(agent),@step,@reset);
before=getLearnableParameters(getActor(agent));
train(agent,env,rlTrainingOptions('MaxEpisodes',2,'MaxStepsPerEpisode',512,'Plots','none','Verbose',true,'UseParallel',false));
after=getLearnableParameters(getActor(agent));assert(~isequaln(before,after));
save(fullfile(fixture,'trained.mat'),'agent');z=load(fullfile(fixture,'trained.mat'));net=getModel(getActor(z.agent));
idx=find(strcmp({net.Layers.Name},'sdev'));assert(net.Layers(idx).Scale==.5);
assert(strcmp(hash,checkpointreview.sha256(src)));
fprintf('PASS fork/save/load, 150-step mean/std replay, snapshot factory/validator, repeated scaling rejection, synthetic CPU PPO update and reload; parent unchanged. No flight training.\n');
end
function [obs,state]=reset()
state=0;obs=zeros(10,1);
end
function [obs,reward,done,state]=step(action,state)
state=state+1;obs=ones(10,1)*sin(state*.1);reward=1-double(action)^2;done=state>=512;
end
