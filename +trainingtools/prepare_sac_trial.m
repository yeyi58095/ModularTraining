function info=prepare_sac_trial(recipe)
% Independent eight-stage SAC run, prepared only. No PPO conversion or launch.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
if nargin<1,recipe='sac_serial_cpu_trial.json';end
assert(any(strcmp(recipe,{'sac_serial_cpu_trial.json','lab_gpu6_sac_spatial_v2.json'})),'SAC:Recipe','Unknown SAC recipe.');
trainingtools.prepare_progressive_v2_training();
cfg=jsondecode(fileread(fullfile(root,'configs',recipe)));
assert(~cfg.start && cfg.maxAttempts==1);
cfg.curriculum=fullfile(root,cfg.curriculum);
plan=trainingcurriculum.load_plan(cfg.curriculum,true);
assert(strcmp(plan.model,'sac_lstm128') && numel(plan.stages)==8);
args=namedargs2cell(cfg); info=retry(args{:});
fprintf('Prepared fresh SAC only; first launch is bounded to one attempt, at most %d episodes.\n',cfg.episodesPerProcess);
end
