function report=test_spatial_v2_simulation()
% One full frozen-policy replay, in an isolated fixture. Never resume training.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
source=fullfile(root,'diagnostic_packages','stage6_review','main');
reference=fullfile(source,'reports','evaluation_20261014_090252_tpa0964215');
assert(isfile(fullfile(reference,'evaluation.json')),'Test:MissingData','Local diagnostic traces required.');
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);
for name={'curriculum.json','curriculum_assets','model.json'}
    copyfile(fullfile(source,name{1}),fullfile(fixture,name{1}));
end
mkdir(fullfile(fixture,'checkpoints'));
checkpoint=fullfile(source,'checkpoints','Agent31600.mat');before=checkpointreview.sha256(checkpoint);
copyfile(checkpoint,fullfile(fixture,'checkpoints','Agent31600.mat'));
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','paused'));
fid=fopen(fullfile(fixture,'supervisor.lock'),'w');fclose(fid);
[manifest,assets]=trainingenv.registry(root,'spatial_v2');trainingenv.snapshot(manifest,assets,fixture);
report=compare_training_checkpoints(fixture,episodes=31600,includeLatest=false, ...
    stages=6,seeds=205,maxSteps=3000,rewardDiagnostics=true);
audit=audit_training_rewards(report.outputDir);
assert(report.weights_unchanged && strcmp(report.environment_id,'spatial_v2'));
assert(strcmp(audit.results{1}.reward_version,'spatial_reward_v2'));
assert(strcmp(before,checkpointreview.sha256(checkpoint)));
oldReport=jsondecode(fileread(fullfile(reference,'evaluation.json')));
oldRows=oldReport.results;if iscell(oldRows),oldRows=[oldRows{:}];end
oldRow=oldRows([oldRows.seed]==205);assert(isscalar(oldRow));
old=load(fullfile(reference,oldRow.trace),'experience','diagnostics');
new=load(fullfile(report.outputDir,report.results{1}.trace),'experience','diagnostics');
d=old.diagnostics.getElement('guidance_d').Values.Data;d=double(d(2:end));
cross=old.diagnostics.getElement('reward_cross_track').Values.Data;
bonus=old.diagnostics.getElement('reward_distance_bonus').Values.Data;
oldReward=double(old.experience.Reward.Data(:));
expected=oldReward-double(cross(2:end))-double(bonus(2:end))+.2-.2*d/30+.1+.05*max(0,1-d/10);
actual=double(new.experience.Reward.Data(:));
assert(numel(actual)==3000 && max(abs(actual-expected))<1e-8,'Test:Score','Actual v2 differs from offline candidate.');
for signal={'guidance_d','P_E','P_N','phi','psi','reward_action_change'}
    a=old.diagnostics.getElement(signal{1}).Values;b=new.diagnostics.getElement(signal{1}).Values;
    assert(isequal(size(a.Data),size(b.Data)) && max(abs(double(a.Data(:))-double(b.Data(:))))<1e-8, ...
        'Test:Trajectory','Frozen-policy trajectory/control penalty changed.');
end
trainingcurriculum.write_json(fullfile(root,'tests','output','spatial_v2_validation.json'), ...
    struct('evaluation',report.outputDir,'model_sha256',report.model_sha256, ...
    'steps',numel(actual),'new_reward',sum(actual),'old_reward',sum(oldReward), ...
    'max_reward_residual',max(abs(actual-expected)),'source_checkpoint_unchanged',true, ...
    'scope','Frozen Agent31600 Stage6 seed205; no training or convergence validation'));
fprintf('PASS actual spatial_v2: 3000 steps, offline reward agreement, unchanged flight signals and checkpoint.\n');
end
