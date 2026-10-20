function test_pending_reviews()
% Frozen continuous-flight replay and shadow history review; no training.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
source=fullfile(root,'artifacts','results','result-20261017_071436_recovery_tp323769ed-e177d217bc1f');
evaluation=fullfile(source,'reports','evaluation_20261019_075841_tpdf0ef65f');
checkpoint=fullfile(source,'Agent_Success.mat');
continuous=trainingtools.simulate_continuous_flight(checkpoint,fullfile(evaluation,'scenarios.mat'), ...
    "random_full_wind",902);
assert(continuous.steps==3000);
trainingcurriculum.write_json(fullfile(root,'tests','output','continuous-flight-validation.json'),continuous);
% Review the existing exploration trace, not the new no-exploration simulation.
trace=load(fullfile(evaluation,'ep39300_stage8_seed902.mat'),'experience');
names=fieldnames(trace.experience.Observation);series=trace.experience.Observation.(names{1});
obs=reshape(double(series.Data),10,[]);time=double(series.Time(:));
distance=abs(obs(7,:))*30;valid=time>=10;
indices=find(valid);[maximum,j]=max(distance(valid));peak=indices(j);
actionNames=fieldnames(trace.experience.Action);
action=trace.experience.Action.(actionNames{1});a=double(action.Data(:));t=double(action.Time(:));
near=t>=time(peak)-5 & t<=time(peak)+5;
result=struct('scope','saved exploration trace, observation-derived evidence, not physical cause', ...
    'peak_after_10s_m',maximum,'peak_time_s',time(peak), ...
    'roll_at_peak_deg',obs(3,peak)*40,'near_peak_action_min',min(a(near)), ...
    'near_peak_action_max',max(a(near)), ...
    'near_peak_raw_action_abs_ge_0_99_fraction',mean(abs(a(near))>=.99), ...
    'near_peak_raw_action_outside_declared_range_fraction',mean(abs(a(near))>1), ...
    'source_sha256',checkpointreview.sha256(fullfile(evaluation,'ep39300_stage8_seed902.mat')));
trainingcurriculum.write_json(fullfile(root,'tests','output','stage8-902-review.json'),result);disp(result);
% The archive is immutable: copy only required inputs into a test fixture.
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);mkdir(fullfile(fixture,'checkpoints'));
for name={'curriculum.json','curriculum_assets','curriculum_state.json'}
    copyfile(fullfile(source,name{1}),fullfile(fixture,name{1}));
end
copyfile(checkpoint,fullfile(fixture,'checkpoints','Agent39300.mat'));
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','paused'));
fid=fopen(fullfile(fixture,'supervisor.lock'),'w');fclose(fid);
before=checkpointreview.sha256(fullfile(fixture,'curriculum_state.json'));
shadow=trainingtools.shadow_learning_review(fixture,39300);
assert(shadow.actions_executed==0 && numel(shadow.rows)==393);
assert(strcmp(before,checkpointreview.sha256(fullfile(fixture,'curriculum_state.json'))));
for k=1:numel(shadow.rows)
    row=shadow.rows{k};
    assert(row.health.last_window_end_episode<=row.episode);
    assert(row.stage_start_episode<row.episode);
end
trainingcurriculum.write_json(fullfile(root,'tests','output','shadow-validation.json'), ...
    struct('passed',true,'rows',numel(shadow.rows),'report',shadow.outputDir,'source_unchanged',true));
fprintf('PASS: full continuous replay, original done logged, Stage8 evidence and read-only shadow replay.\n');
end
