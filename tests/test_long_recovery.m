function test_long_recovery()
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
source=receipt.sessionDir;before=checkpointreview.sha256(fullfile(source,'control.json'));
settings=jsondecode(fileread(fullfile(root,'configs','recovery_actor_half.json')));
settings.checkpoint_episode=2;settings.actor_learning_rate_scale=1;
settings.episodes_per_process=1000;settings.max_additional_episodes=2000;
settings.guard.window=100;
file=[tempname(fullfile(root,'tests','output')) '.json'];
trainingcurriculum.write_json(file,settings);
child=trainingtools.prepare_recovery_training(source,file);
cfg=jsondecode(fileread(fullfile(child.sessionDir,'control.json')));
rules=jsondecode(fileread(fullfile(child.sessionDir,'training_guard.json')));
assert(cfg.episodesPerProcess==1000 && rules.window==100 && isfile(fullfile(child.sessionDir,'STOP')));
assert(strcmp(before,checkpointreview.sha256(fullfile(source,'control.json'))));
settings.episodes_per_process=500;trainingcurriculum.write_json(file,settings);
child=trainingtools.prepare_recovery_training(source,file);
cfg=jsondecode(fileread(fullfile(child.sessionDir,'control.json')));
assert(cfg.episodesPerProcess==500);
assert(strcmp(before,checkpointreview.sha256(fullfile(source,'control.json'))));
fprintf('PASS: 500/1000-episode child preparation with 100-episode guard, parent unchanged, no launch.\n');
end
