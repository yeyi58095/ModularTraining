function test_checkpoint_comparison_guards()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
out=fullfile(root,'tests','output'); fixture=tempname(out); mkdir(fixture);
fid=fopen(fullfile(fixture,'supervisor.lock'),'w'); fclose(fid);
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','running'));
try
    compare_training_checkpoints(fixture);
    error('Test:Unexpected','Active session was accepted.');
catch err
    assert(strcmp(err.identifier,'Evaluation:Active'));
end
assert(~isfolder(fullfile(fixture,'reports')));
% t=0 reward is a real transition, not a disposable initialization sample.
e.Reward=timeseries([1;2;3],(0:2)'*.1);
e.IsDone=timeseries([0;0;0],(0:2)'*.1);
e.Observation.observation=timeseries(ones(10,1,4),(0:3)'*.1);
e.Action.action=timeseries([0;.99;-1],(0:2)'*.1);
r=checkpointreview.summarize(e,3);
assert(r.reward==6 && r.steps==3 && r.reached_step_limit);
assert(strcmp(r.end_signal,'step_limit') && r.action_saturation_fraction==2/3);
e.IsDone.Data(end)=1; r=checkpointreview.summarize(e,10);
assert(r.environment_done && ~r.reached_step_limit && strcmp(r.end_signal,'environment_done'));
fprintf('PASS evaluation guard and transition summaries. No simulation started.\n');
end
