function test_checkpoint_comparison()
% Explicit, short SIMULATION ONLY. Uses a previously saved local smoke run.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
session=receipt.sessionDir;
files={'curriculum_state.json','control.json','status.json','Agent_Final.mat'};
before=cellfun(@(f) checkpointreview.sha256(fullfile(session,f)),files,'UniformOutput',false);
priorRng=rng;
report=compare_training_checkpoints(session,episodes=[1 2],includeLatest=true, ...
    stages=[1 2],seeds=101,maxSteps=5);
assert(strcmp(report.status,'complete') && report.weights_unchanged);
assert(numel(report.results)==6 && report.checkpoints{3}.episode==3);
assert(all(cellfun(@(r) r.steps==5,report.results)));
assert(isequal(priorRng,rng) && ~bdIsLoaded('FAFA_Simulation'));
for i=1:numel(files)
    assert(strcmp(before{i},checkpointreview.sha256(fullfile(session,files{i}))));
end
trainingcurriculum.write_json(fullfile(root,'tests','output','evaluation-smoke-latest.json'),report);
fprintf('PASS: 6 real CPU simulations including latest, five steps each; source files and weights unchanged.\n');
end
