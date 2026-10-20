function info=prepare_sac_trial()
% Independent eight-stage SAC run, prepared only. No PPO conversion or launch.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
trainingtools.prepare_progressive_v2_training();
cfg=jsondecode(fileread(fullfile(root,'configs','lab_gpu6_sac_spatial_v2.json')));
assert(~cfg.start && cfg.maxAttempts==1);
cfg.curriculum=fullfile(root,cfg.curriculum);
plan=trainingcurriculum.load_plan(cfg.curriculum,true);
assert(strcmp(plan.model,'sac_lstm128') && numel(plan.stages)==8);
args=namedargs2cell(cfg); info=retry(args{:});
fprintf('Prepared fresh SAC only; first launch is bounded to one attempt, at most 1000 episodes.\n');
end
