function child=prepare_sac_wind_slow()
% Prepare one bounded actor-rate branch from the audited weak-wind Agent1100.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; restore=onCleanup(@() path(oldPath));
addpath(root,fullfile(root,'runtime'));
receipt=fullfile(root,'artifacts','sac-wind-actor-half-1100-run.txt');
lock=System.IO.File.Open([receipt '.lock'],System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose());
assert(~isfile(receipt),'SAC:Receipt','Child receipt already exists. Inspect the existing child.');
source=string(strtrim(fileread(fullfile(root,'artifacts','sac-weak-wind-1000-run.txt'))));
[~,id]=fileparts(source);
assert(id=="20261105_210649_recovery_tpb199bcee",'SAC:Source','Unexpected source run.');
spec=jsondecode(fileread(fullfile(source,'model.json')));
cfg=jsondecode(fileread(fullfile(source,'control.json')));
state=jsondecode(fileread(fullfile(source,'curriculum_state.json')));
plan=trainingcurriculum.load_plan(fullfile(source,'curriculum.json'),true);
assert(strcmp(spec.name,'sac_paper64') && strcmp(plan.environment,'spatial_v2') && ...
    state.stage_index==2 && state.start_episode==1000 && ...
    strcmp(plan.stages{2}.id,'random_weak_wind') && ...
    strcmp(cfg.trainingDevice,'gpu') && strcmp(cfg.executionMode,'parallel') && ...
    cfg.numWorkers==6 && cfg.minWorkers==6 && cfg.checkpointEvery==100, ...
    'SAC:Settings','Unexpected source configuration.');
info=trainingtools.prepare_recovery_training(source,fullfile(root,'configs','sac_wind_actor_half_1100.json'));
child=string(info.sessionDir);
retry(resume=child,maxAttempts=1,start=false);
temporary=[tempname(fileparts(receipt)) '.txt'];
writelines(child,temporary); movefile(temporary,receipt);
fprintf('Prepared child receipt:\n%s\nStart explicitly with retry(resume=child,start=true).\n',receipt);
end
