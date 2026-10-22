function pair=prepare_sac_replay_pair(sourceSession,episode)
% Prepare only: two bounded SAC children, parent unchanged. Never train here.
arguments
    sourceSession (1,1) string
    episode (1,1) double {mustBeInteger,mustBePositive} = 1100
end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
assert(isfolder(sourceSession),'SAC:Source','Supply an existing absolute parent path.');
assert(java.io.File(char(sourceSession)).isAbsolute(),'SAC:Source','Absolute parent path required.');
spec=jsondecode(fileread(fullfile(sourceSession,'model.json')));
cfg=jsondecode(fileread(fullfile(sourceSession,'control.json')));
assert(strcmp(spec.algorithm,'SAC') && spec.experienceBufferLength==100000);
assert(strcmp(cfg.executionMode,'serial') && strcmp(cfg.trainingDevice,'cpu'));
out=fullfile(root,'artifacts','sac-replay-pairs');if ~isfolder(out),mkdir(out);end
batch=tempname(out);mkdir(batch);
settings=jsondecode(fileread(fullfile(root,'configs','recovery_actor_half.json')));
settings.checkpoint_episode=episode;settings.actor_learning_rate_scale=1;
settings.episodes_per_process=500;settings.max_additional_episodes=1000;
if isfile(fullfile(sourceSession,'training_guard.json'))
    settings.guard=jsondecode(fileread(fullfile(sourceSession,'training_guard.json')));
    if isfield(settings.guard,'budget_enabled'),assert(settings.guard.budget_enabled);end
    if isfield(settings.guard,'regression_action'),assert(~strcmp(settings.guard.regression_action,'monitor'));end
end
capacities=[100000 500000];children=cell(1,2);
for k=1:2
    settings.experience_buffer_length=capacities(k);
    recipe=fullfile(batch,sprintf('recipe-%d.json',capacities(k)));
    trainingcurriculum.write_json(recipe,settings);
    children{k}=trainingtools.prepare_recovery_training(sourceSession,recipe);
    retry(resume=children{k}.sessionDir,maxAttempts=1,fastRestart='off',start=false);
end
a=jsondecode(fileread(fullfile(children{1}.sessionDir,'recovery.json')));
b=jsondecode(fileread(fullfile(children{2}.sessionDir,'recovery.json')));
assert(strcmp(a.parent_sha256,b.parent_sha256) && ...
    strcmp(a.parent_curriculum_sha256,b.parent_curriculum_sha256) && ...
    strcmp(a.parent_model_sha256,b.parent_model_sha256),'SAC:Pair','Parent changed between preparations.');
pair=struct('source',char(sourceSession),'parentEpisode',episode, ...
    'baseline',children{1}.sessionDir,'largerReplay',children{2}.sessionDir, ...
    'parentSHA256',a.parent_sha256,'status','prepared_only','receipt',fullfile(batch,'pair.json'));
trainingcurriculum.write_json(pair.receipt,pair);
disp(pair);
fprintf('No training started. Keep parent paused; do not launch both children together.\n');
end
