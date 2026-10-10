function test_resume_audit()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
r=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
file=fullfile(r.sessionDir,'checkpoints','Agent1.mat');
before=checkpointreview.sha256(file);
fixture=tempname(fullfile(root,'tests','output')); mkdir(fixture);
mkdir(fullfile(fixture,'checkpoints')); initialDir=fullfile(fixture,'runs','r000001'); mkdir(initialDir);
for ep=1:3
    copyfile(fullfile(r.sessionDir,'checkpoints',sprintf('Agent%d.mat',ep)),fullfile(fixture,'checkpoints'));
end
fid=fopen(fullfile(fixture,'supervisor.lock'),'w'); fclose(fid);
trainingcurriculum.write_json(fullfile(fixture,'status.json'),struct('state','paused'));
copyfile(file,fullfile(initialDir,'Agent_Initial.mat'));
resumeAgentFile='Z:\old_machine\checkpoints\Agent1.mat'; numWorkers=1;
optionsForDisk=struct('ParallelizationOptions',struct('WorkerRandomSeeds',10001));
save(fullfile(initialDir,'TrainingOptions.mat'),'resumeAgentFile','numWorkers','optionsForDisk');
a=audit_training_resume(fixture,episodes=[1 2 3]);
assert(numel(a.checkpoints)==3 && a.checkpoints{1}.actor_vs_first.exact_equal);
assert(a.initial_snapshot_count==1,'Expected synthetic initial snapshot backed by a real agent.');
for k=1:numel(a.initial_snapshots)
    row=a.initial_snapshots{k};
    assert(row.actor_vs_resume.exact_equal && row.critic_vs_resume.exact_equal);
    assert(row.options_equal);
end
assert(strcmp(before,checkpointreview.sha256(file)));
fprintf('PASS resume audit on saved real checkpoints and initial snapshots. No training or simulation.\n');
end
