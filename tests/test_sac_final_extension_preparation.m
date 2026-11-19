function test_sac_final_extension_preparation()
% Real 500k1700 final, preparation only; no train, sim or pool.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@()path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
source=tempname(fullfile(root,'tests','output'));mkdir(source);
payload=fullfile(root,'artifacts','incoming','sac-replay-replication-20261119','payload','retained500k');
for f=["Agent_Final.mat","control.json","curriculum.json","curriculum_state.json","model.json","status.json","environment.json"],copyfile(fullfile(payload,f),source);end
assets=fullfile(root,'artifacts','incoming','sac-actor-half-1500-package-20261107','20261107_002801_recovery_tpbb65eb4c');
for d=["environment","model_source"],copyfile(fullfile(assets,d),fullfile(source,d));end
cfg=jsondecode(fileread(fullfile(source,'control.json')));cfg.curriculumName='sac_final_extension_fixture';trainingcurriculum.write_json(fullfile(source,'control.json'),cfg);
id=fopen(fullfile(source,'supervisor.lock'),'w');fclose(id);
file=fullfile(source,'Agent_Final.mat');sha=checkpointreview.sha256(file);
r=struct('schema_version',1,'checkpoint_source','final','checkpoint_episode',1700,'expected_checkpoint_sha256',sha, ...
    'actor_learning_rate_scale',1,'expected_actor_learning_rate',1.5e-4,'experience_buffer_length',500000, ...
    'episodes_per_process',50,'max_additional_episodes',50, ...
    'guard',struct('schema_version',1,'window',50,'patience',3,'reward_ratio',.5,'steps_ratio',.5,'min_reference_reward',500,'min_reference_steps',500));
recipe=fullfile(source,'recipe.json');trainingcurriculum.write_json(recipe,r);
info=trainingtools.prepare_recovery_training(string(source),string(recipe));
assert(strcmp(checkpointreview.sha256(fullfile(info.sessionDir,'checkpoints','Agent1700.mat')),sha));
g=jsondecode(fileread(fullfile(info.sessionDir,'training_guard.json')));cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(g.origin_episode==1700 && g.max_additional_episodes==50 && cfg.checkpointEvery==50 && cfg.episodesPerProcess==50);
assert(info.stageIndex==2 && isfile(fullfile(info.sessionDir,'STOP')) && isempty(dir(fullfile(info.sessionDir,'attempt_*'))));
r.actor_learning_rate_scale=.5;trainingcurriculum.write_json(recipe,r);
try,trainingtools.prepare_recovery_training(string(source),string(recipe));error('Test:Expected','Expected refusal');catch e,assert(strcmp(e.identifier,'Recovery:FinalScope'));end
assert(strcmp(checkpointreview.sha256(file),sha));
fprintf('FINAL_EXTENSION_PREPARATION_OK: exact final bytes/state, 1700 origin, budget50, no attempt, parameter mutation refused.\n');
end
