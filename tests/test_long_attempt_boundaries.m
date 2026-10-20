function test_long_attempt_boundaries()
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
stage=struct('id','test','max_episodes',2000,'on_limit','pause', ...
    'advance_when',struct('metric','reward_mean','window',100,'consecutive_windows',3,'at_least',10));
stats=struct('EpisodeIndex',(1:300)','EpisodeReward',10*ones(300,1),'EpisodeSteps',3000*ones(300,1));
assert(trainingcurriculum.progress_callback(stats,stage,1,2,0,1000,100,[]));
stats.EpisodeReward(:)=1;
assert(~trainingcurriculum.progress_callback(stats,stage,1,2,0,1000,100,[]));
rule=struct('schema_version',1,'window',100,'patience',2,'reward_ratio',.8,'steps_ratio',.8, ...
    'min_reference_reward',5,'min_reference_steps',1000,'origin_episode',0, ...
    'max_additional_episodes',2000);
stats.EpisodeReward(1:100)=10;stats.EpisodeSteps(101:end)=500;
assert(trainingcurriculum.progress_callback(stats,stage,1,2,0,1000,100,rule));
rule.regression_action='monitor';rule.budget_enabled=false;
assert(~trainingcurriculum.progress_callback(stats,stage,1,2,0,1000,100,rule));
% Do not stop off-boundary, and do not mix a previous stage into this stage.
stats.EpisodeIndex=(1:299)';stats.EpisodeReward=10*ones(299,1);stats.EpisodeSteps=3000*ones(299,1);
assert(~trainingcurriculum.progress_callback(stats,stage,1,2,0,1000,100,[]));
stats.EpisodeIndex=(1:300)';stats.EpisodeReward=10*ones(300,1);stats.EpisodeSteps=3000*ones(300,1);
assert(~trainingcurriculum.progress_callback(stats,stage,2,2,200,1000,100,[]));
assert(trainingcurriculum.progress_callback(stats,stage,2,2,200,300,100,[]));
fprintf('PASS: 1000-episode attempts retain 100-episode transition/regression checks; monitor and stage isolation.\n');
end
