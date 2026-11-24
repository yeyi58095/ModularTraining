function manifest=review_sac_roll_oscillation(bundle,output)
% Replay two frozen SAC endpoints on a straight path with three fixed winds.
arguments
    bundle (1,1) string
    output (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));
bundle=string(trainingtools.local_data_path(root,bundle));
output=string(trainingtools.local_data_path(root,output));
ledger=readJson(fullfile(bundle,'schedule.json'));
assert(strcmp(ledger.status,'complete'),'RollReview:Running', ...
    'The four-stage schedule and final audit must be complete.');
assert(~isfolder(output) && ~isfile(output),'RollReview:Existing', ...
    'Choose a new output directory to preserve any earlier review.');
session=string(trainingtools.local_data_path(root,string(ledger.session)));
status=readJson(fullfile(session,'status.json'));
assert(strcmp(status.state,'paused') && status.attempt==4,'RollReview:RunStatus', ...
    'Expected the completed fourth attempt to be paused.');
[model,environment]=trainingenv.resolve(session);
modelHash=checkpointreview.sha256(model);
assert(strcmp(environment.id,'spatial_v2') && ...
    strcmp(modelHash,'997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557'), ...
    'RollReview:Signals','Roll scale and port tracing were verified for this spatial_v2 snapshot.');
episodes=[1700 2000];
phases=[3 4];
for k=1:numel(episodes)
    directory=fullfile(bundle,sprintf('audit_stage%d',phases(k)));
    summary=readJson(fullfile(directory,'summary.json'));
    source=fullfile(directory,'Agent_Final.mat');
    hash=checkpointreview.sha256(source);
    assert(summary.phase==phases(k) && summary.episode==episodes(k) && ...
        strcmp(hash,summary.checkpoint_sha256) && ...
        strcmp(modelHash,summary.environment_model_sha256), ...
        'RollReview:Source','Endpoint or environment does not match its audit.');
    endpoints(k)=struct('episode',episodes(k),'source',char(source),'sha256',hash); %#ok<AGROW>
end
assert(strcmp(checkpointreview.sha256(fullfile(session,'Agent_Final.mat')),endpoints(2).sha256), ...
    'RollReview:Final','Active run final differs from the audited fourth-stage checkpoint.');

fixture=fullfile(output,'fixture');
checkpoints=fullfile(fixture,'checkpoints');
mkdir(checkpoints);
for k=1:numel(endpoints)
    copy=fullfile(checkpoints,sprintf('Agent%d.mat',endpoints(k).episode));
    copyfile(endpoints(k).source,copy);
    assert(strcmp(checkpointreview.sha256(copy),endpoints(k).sha256), ...
        'RollReview:Copy','Copied checkpoint differs from its audited source.');
end
trainingenv.snapshot(fullfile(session,'environment.json'),fileparts(model),fixture);
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','paused'));
lock=fopen(fullfile(fixture,'supervisor.lock'),'w');
assert(lock>=0,'RollReview:Lock','Unable to initialize the review fixture lock.');
fclose(lock);

% Same straight geometry used by the linked nominal roll research.
east=unique([(50:1.5:1000)';1000]);
waypoints=[east zeros(size(east)) 70*ones(size(east))];
velocity=repmat([15 0 0],numel(east),1);
save(fullfile(fixture,'straight.mat'),'waypoints','velocity');
course=trainingcurriculum.load_plan(fullfile(bundle,'official_curriculum.json'),true);
template=rmfield(course.stages{1},'frozen_gate');
names={'calm','oblique_wind','crosswind_turbulence'};
wind=[0 0 0;2 2 1;0 3 2];
for k=1:numel(names)
    stage=template;
    stage.id=names{k};
    stage.trajectory=struct('type','mat','file','straight.mat', ...
        'waypoints_variable','waypoints','velocity_variable','velocity');
    stage.wind=struct('east_mps',repelem(wind(k,1),2), ...
        'north_mps',repelem(wind(k,2),2),'turbulence',repelem(wind(k,3),2));
    stages{k}=stage; %#ok<AGROW>
end
course.stages=stages;
trainingcurriculum.write_json(fullfile(fixture,'curriculum.json'),course);
result=compare_training_checkpoints(fixture,episodes=episodes,includeLatest=false, ...
    stages=1:numel(names),seeds=2000000101,maxSteps=500, ...
    diagnostics=true,routeMetrics=true,useExploration=false);
assert(strcmp(result.status,'complete') && result.weights_unchanged && ...
    numel(result.results)==numel(episodes)*numel(names) && ...
    strcmp(result.model_sha256,modelHash) && strcmp(checkpointreview.sha256(model),modelHash), ...
    'RollReview:Result','The straight-route comparison is incomplete.');
for k=1:numel(endpoints)
    assert(result.checkpoints{k}.episode==endpoints(k).episode && ...
        strcmp(result.checkpoints{k}.sha256,endpoints(k).sha256) && ...
        strcmp(checkpointreview.sha256(endpoints(k).source),endpoints(k).sha256), ...
        'RollReview:Endpoint','An endpoint did not match its verified source.');
end
for k=1:numel(result.results)
    row=result.results{k};
    data=load(fullfile(result.outputDir,row.trace),'experience','diagnostics');
    series=data.experience.Action;
    fields=fieldnames(series);
    assert(isscalar(fields),'RollReview:Action','Expected a single bank action.');
    action=series.(fields{1});
    time=double(action.Time(:));
    command=40*double(action.Data(:));
    measured=rad2deg(atTime(data.diagnostics.getElement('phi').Values,time));
    east=atTime(data.diagnostics.getElement('P_E').Values,time);
    north=atTime(data.diagnostics.getElement('P_N').Values,time);
    keep=isfinite(time)&isfinite(command)&isfinite(measured)&isfinite(east)&isfinite(north);
    assert(any(keep),'RollReview:Time','No overlap between action and measured signals.');
    filename=sprintf('roll_ep%d_%s.csv',row.checkpoint_episode,row.stage_id);
    traceTable=table(time(keep),command(keep),measured(keep),east(keep),north(keep), ...
        'VariableNames',{'time_s','bank_command_deg','measured_roll_deg','east_m','north_m'});
    writetable(traceTable,fullfile(output,filename));
    cases(k)=struct('episode',row.checkpoint_episode,'scenario',row.stage_id, ...
        'wind',[row.wind_east_mps,row.wind_north_mps,row.turbulence], ...
        'trace_csv',filename,'steps',row.steps,'environment_done',row.environment_done, ...
        'reward',row.reward,'route_metrics',row.route_metrics); %#ok<AGROW>
end
manifest=struct('schema_version',1,'environment',environment.id, ...
    'environment_sha256',result.model_sha256,'checkpoint_sources',{endpoints}, ...
    'evaluation',fullfile(result.outputDir,'evaluation.json'),'cases',{cases}, ...
    'measured_signal','OBSERVATION/phi in rad, converted to deg', ...
    'bank_command_signal','RL Agent scalar action times 40 deg, per spatial_v2 inner loop Gain2', ...
    'alignment','Linear interpolation of measured phi and position at original policy action times', ...
    'route_start_east_m',50,'route_end_east_m',1000,'route_north_m',0, ...
    'policy_sample_seconds',.1,'fixed_scenario_seed',2000000101, ...
    'exploration',false,'retains_environment_done',true);
trainingcurriculum.write_json(fullfile(output,'roll_cases.json'),manifest);
fprintf('Saved six aligned roll traces: %s\n',output);
end

function values=atTime(signal,target)
[sampleTimes,index]=unique(double(signal.Time(:)),'last');
data=double(signal.Data(:));
assert(numel(data)==numel(signal.Time) && numel(sampleTimes)>=2, ...
    'RollReview:Signal','Expected a scalar signal with at least two time samples.');
values=interp1(sampleTimes,data(index),target,'linear',NaN);
end

function data=readJson(file)
data=jsondecode(fileread(file));
end
