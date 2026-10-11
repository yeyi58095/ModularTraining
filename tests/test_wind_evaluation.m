function test_wind_evaluation()
% Paired scenarios plus real, short CPU SIMULATION ONLY using an existing agent.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
plan=trainingcurriculum.load_plan(fullfile(root,'experiments','progressive_v1','curriculum.json'),false);
global TARGET_SPEED DT WAYPOINT_SPACING
old={TARGET_SPEED,DT,WAYPOINT_SPACING}; cleanup=onCleanup(@() restore(old)); %#ok<NASGU>
TARGET_SPEED=15; DT=.1; WAYPOINT_SPACING=1.5;
prior=rng;
a=checkpointreview.scenario(plan.stages{4},root,201);
b=checkpointreview.scenario(plan.stages{5},root,201);
c=checkpointreview.scenario(plan.stages{5},root,202);
assert(isequal(prior,rng) && isequal(a.waypoints,b.waypoints));
assert(~isequal(b.waypoints,c.waypoints));
assert(isequal(b,checkpointreview.scenario(plan.stages{5},root,201)));
assert(all(a.wind==0) && all(abs(b.wind(1:2))<=1) && ismember(b.wind(3),[0 1]));
e.Reward.Data=[1;2]; e.IsDone.Data=[false;true];
e.Observation.obs.Data=zeros(10,2); e.Observation.obs.Data(7,end)=1.7;
e.Action.action.Data=[0;0];
r=checkpointreview.summarize(e,2); assert(strcmp(r.termination_evidence,'distance_threshold'));
e.Observation.obs.Data(3,end)=1.1;
r=checkpointreview.summarize(e,2); assert(strcmp(r.termination_evidence,'distance_and_roll_thresholds'));
e.Observation.obs.Data(:)=0;
r=checkpointreview.summarize(e,2); assert(strcmp(r.termination_evidence,'unknown'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
fixture=tempname(fullfile(root,'tests','output')); mkdir(fixture); mkdir(fullfile(fixture,'checkpoints'));
source=fullfile(receipt.sessionDir,'checkpoints','Agent3.mat');
sourceHash=checkpointreview.sha256(source);
copyfile(source,fullfile(fixture,'checkpoints','Agent3.mat'));
fid=fopen(fullfile(fixture,'supervisor.lock'),'w'); fclose(fid);
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','paused'));
plan.stages=plan.stages(4:5);
% Force nonzero wind/turbulence for integration coverage.
plan.stages{2}.wind=struct('east_mps',[1 1],'north_mps',[-1 -1],'turbulence',[1 1]);
trainingcurriculum.write_json(fullfile(fixture,'curriculum.json'),plan);
report=compare_training_checkpoints(fixture,episodes=3,includeLatest=false, ...
    stages=[1 2],seeds=[201 202],maxSteps=5);
assert(strcmp(report.status,'complete') && report.weights_unchanged);
assert(numel(report.results)==4 && numel(report.summary)==2);
assert(report.results{3}.wind_east_mps==1 && report.results{3}.turbulence==1);
assert(strcmp(sourceHash,checkpointreview.sha256(source)));
assert(isequal(prior,rng) && ~bdIsLoaded('FAFA_Simulation'));
assert(all(cellfun(@(x) x.steps==5,report.results)));
fprintf('PASS paired seeded scenarios, terminal evidence, four real CPU simulations; source unchanged.\n');
end
function restore(old)
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=old{1}; DT=old{2}; WAYPOINT_SPACING=old{3};
end
