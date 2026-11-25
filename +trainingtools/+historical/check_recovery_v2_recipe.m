function check_recovery_v2_recipe(checkpoint)
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
previousPath = path;
restorePath = onCleanup(@() path(previousPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
c=jsondecode(fileread(fullfile(root,'configs','recovery_v2_18000_guarded.json')));
if nargin == 0
    checkpoint = fullfile('diagnostic_packages','regression_models_20261016','checkpoints','Agent18400.mat');
end
p=trainingtools.local_data_path(root,checkpoint);
[h,ep]=checkpoint_resume_state(p);assert(ep==18400);
r=trainingguard.assess(h.EpisodeReward(1:18000),h.EpisodeSteps(1:18000),14300,c.guard);disp(r);assert(~r.suspected_regression);
a=trainingguard.assess([ones(100,1)*2600;ones(200,1)*1000],[ones(100,1)*3000;ones(200,1)*1000],0,c.guard);assert(a.suspected_regression);
a=trainingguard.assess([ones(100,1)*2600;ones(100,1)*1000],[ones(100,1)*3000;ones(100,1)*1000],0,c.guard);assert(~a.suspected_regression);
x=load(p);if isfield(x,'saved_agent'),agent=x.saved_agent;else,agent=x.Agent_Stage2;end
before=getLearnableParameters(getActor(agent));assert(agent.AgentOptions.ActorOptimizerOptions.LearnRate==c.expected_actor_learning_rate);
agent.AgentOptions.ActorOptimizerOptions.LearnRate=c.expected_actor_learning_rate*c.actor_learning_rate_scale;
assert(isequaln(before,getLearnableParameters(getActor(agent))));assert(agent.AgentOptions.ActorOptimizerOptions.LearnRate==2.5e-5);
assert(strcmpi(checkpointreview.sha256(fullfile(root,'environments','spatial_v2','FAFA_Simulation.slx')),c.expected_runtime_model_sha256));
fprintf('PASS recipe, source historical guard, two-window pause, one-window tolerance, in-memory rate change preserves actor weights, environment hash. No train/sim.\n');
end
