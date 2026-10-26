function test_sac_mlp_slow_preparation()
% Bounded preparation only; no train or sim. Requires existing MLP flight fixture.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,fullfile(root,'runtime'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','sac-mlp-flight-latest.json')));
source=string(receipt.sessionDir);
parent=fullfile(source,'checkpoints','Agent2.mat');
before=checkpointreview.sha256(parent);
recipe=jsondecode(fileread(fullfile(root,'configs','sac_mlp_2100_actor_slow.json')));
assert(recipe.checkpoint_episode==2100 && recipe.max_additional_episodes==500);
recipe.checkpoint_episode=2;
file=string(tempname(fullfile(root,'tests','output')))+".json";
trainingcurriculum.write_json(file,recipe);
info=trainingtools.prepare_recovery_training(source,file);
child=string(info.sessionDir);
assert(strcmp(checkpoint_storage_version(child),'-v7'));
fid=fopen(fullfile(child,'checkpoints','Agent2.mat'),'r');header=fread(fid,20,'*char')';fclose(fid);
assert(startsWith(header,'MATLAB 5.0 MAT-file'));
assert(abs(info.actorLearnRate-1e-5)<1e-15 && ~info.continuousTraining);
rules=jsondecode(fileread(fullfile(child,'training_guard.json')));
assert(rules.budget_enabled && strcmp(rules.regression_action,'pause'));
assert(rules.origin_episode==2 && rules.max_additional_episodes==500);
lineage=jsondecode(fileread(fullfile(child,'recovery.json')));
assert(strcmp(lineage.parent_sha256,before) && lineage.weights_preserved);
assert(strcmp(checkpointreview.sha256(parent),before));
assert(isfile(fullfile(child,'STOP')) && isempty(dir(fullfile(child,'attempt_*'))));
d=load(fullfile(child,'checkpoints','Agent2.mat'),'Agent_Stage2');
spec=jsondecode(fileread(fullfile(child,'model.json')));
assert(strcmp(spec.name,'sac_mlp128'));
trainingmodels.validate_agent(d.Agent_Stage2,spec);
serialized=saveobj(d.Agent_Stage2);
assert(abs(serialized.ActorOptimizer.LearnRate-1e-5)<1e-15);
fprintf('PASS: MLP slow-actor preparation, disk reload, guard, source hash; no training.\n');
end
