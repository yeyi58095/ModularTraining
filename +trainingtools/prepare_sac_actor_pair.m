function pair=prepare_sac_actor_pair(sourceSession,episode)
% Prepare bounded control/candidate; user launches only one at a time.
arguments
    sourceSession (1,1) string
    episode (1,1) double {mustBeInteger,mustBePositive} = 1600
end
root=fileparts(fileparts(mfilename('fullpath')));
assert(java.io.File(char(sourceSession)).isAbsolute());
spec=jsondecode(fileread(fullfile(sourceSession,'model.json')));
cfg=jsondecode(fileread(fullfile(sourceSession,'control.json')));
assert(strcmp(spec.algorithm,'SAC') && spec.experienceBufferLength==100000 && spec.actorLearnRate==5e-5);
assert(strcmp(cfg.executionMode,'serial') && strcmp(cfg.trainingDevice,'cpu'));
out=fullfile(root,'artifacts','sac-actor-pairs');if ~isfolder(out),mkdir(out);end
batch=tempname(out);mkdir(batch);
settings=jsondecode(fileread(fullfile(root,'configs','recovery_actor_half.json')));
settings.checkpoint_episode=episode;settings.experience_buffer_length=100000;
settings.episodes_per_process=500;settings.max_additional_episodes=500;
settings.expected_actor_learning_rate=5e-5;
if isfile(fullfile(sourceSession,'training_guard.json'))
    settings.guard=jsondecode(fileread(fullfile(sourceSession,'training_guard.json')));
    if isfield(settings.guard,'budget_enabled'),assert(settings.guard.budget_enabled);end
    if isfield(settings.guard,'regression_action'),assert(~strcmp(settings.guard.regression_action,'monitor'));end
end
scales=[1 .2];children=cell(1,2);
for k=1:2
    settings.actor_learning_rate_scale=scales(k);
    recipe=fullfile(batch,sprintf('recipe-%d.json',k));
    trainingcurriculum.write_json(recipe,settings);
    children{k}=trainingtools.prepare_recovery_training(sourceSession,recipe);
    retry(resume=children{k}.sessionDir,maxAttempts=1,fastRestart='off',start=false);
end
a=jsondecode(fileread(fullfile(children{1}.sessionDir,'recovery.json')));
b=jsondecode(fileread(fullfile(children{2}.sessionDir,'recovery.json')));
assert(strcmp(a.parent_sha256,b.parent_sha256) && ...
    strcmp(a.parent_curriculum_sha256,b.parent_curriculum_sha256) && ...
    strcmp(a.parent_model_sha256,b.parent_model_sha256));
pair=struct('source',char(sourceSession),'parentEpisode',episode, ...
    'control',children{1}.sessionDir,'candidate',children{2}.sessionDir, ...
    'parentSHA256',a.parent_sha256,'actorRates',[5e-5 1e-5], ...
    'status','prepared_only','receipt',fullfile(batch,'pair.json'));
trainingcurriculum.write_json(pair.receipt,pair);disp(pair);
fprintf('Prepared only. Launch one child explicitly; preserve parent and control.\n');
end
