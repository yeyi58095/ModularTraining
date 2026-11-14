function test_sac_review_preparation()
% Real archived agent, isolated synthetic 2000 parent metadata; no train/sim.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
archive=fullfile(root,'artifacts','incoming','sac-actor-half-1500-package-20261107','20261107_002801_recovery_tpbb65eb4c');
folder=tempname(fullfile(root,'tests','output'));mkdir(folder);
source=fullfile(folder,'20261107_132924_recovery_tp578fea3e');mkdir(source);
for name=["environment","model_source"]
    copyfile(fullfile(archive,name),fullfile(source,name));
end
for name=["environment.json","model.json","curriculum.json","curriculum_state.json","checkpoint_storage.json","control.json"]
    copyfile(fullfile(archive,name),fullfile(source,name));
end
mkdir(fullfile(source,'checkpoints'));
original=fullfile(archive,'checkpoints','Agent1500.mat'); before=checkpointreview.sha256(original);
copyfile(original,fullfile(source,'checkpoints','Agent1500.mat'));
cfg=read(fullfile(source,'control.json'));cfg.curriculumName='sac_review_preparation_fixture';
write(fullfile(source,'control.json'),cfg);
write(fullfile(source,'status.json'),struct('state','paused'));
write(fullfile(source,'curriculum_outcome.json'),struct('episodes',2000,'curriculumReason','recovery_budget'));
write(fullfile(source,'training_guard_state.json'),struct('paused',true,'reason','recovery_budget'));
f=fopen(fullfile(source,'supervisor.lock'),'w');fclose(f);
recipe=read(fullfile(root,'configs','sac_wind_actor_half_extend_1500.json'));
recipe.pilot='sac_wind_review_selected';recipe.expected_run='20261107_132924_recovery_tp578fea3e';
recipe.expected_checkpoint_sha256=before;recipe.selection_evidence=struct('scope','synthetic test only');
file=fullfile(folder,'recipe.json');write(file,recipe);
info=trainingtools.prepare_recovery_training(string(source),string(file));
child=info.sessionDir;
assert(strcmp(checkpointreview.sha256(fullfile(child,'checkpoints','Agent1500.mat')),before));
assert(strcmp(checkpointreview.sha256(original),before));
c=read(fullfile(child,'control.json')); assert(c.maxAttempts==1 && c.episodesPerProcess==500 && c.numWorkers==6);
g=read(fullfile(child,'training_guard.json'));assert(g.origin_episode==1500 && g.max_additional_episodes==500);
assert(isfile(fullfile(child,'STOP')) && isempty(dir(fullfile(child,'attempt_*'))));
s=read(fullfile(child,'curriculum_state.json'));assert(s.stage_index==2 && s.start_episode==1000);
assert(strcmp(checkpointreview.sha256(fullfile(child,'curriculum.json')),checkpointreview.sha256(fullfile(source,'curriculum.json'))));
% Wrong hash must fail without making another child.
recipe.expected_checkpoint_sha256=repmat('0',1,64);write(file,recipe);
try
    trainingtools.prepare_recovery_training(string(source),string(file));error('Test:Expected','Expected hash rejection');
catch e,assert(strcmp(e.identifier,'Recovery:SourceHash'));end
fprintf('REVIEW_PREPARATION_OK: actual Agent1500 byte-preserving fork, budget/STOP/stage retained, bad hash refused; no training.\n');
end
function q=read(file),q=jsondecode(fileread(file));end
function write(file,q),trainingcurriculum.write_json(file,q);end
