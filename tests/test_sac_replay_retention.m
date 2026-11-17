function test_sac_replay_retention()
% Archived paper64; capacity growth + synthetic appends only. No train/sim.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
f=jsondecode(fileread(fullfile(root,'tests','output','sac-paper-probe-fixture.json')));
source=fullfile(f.folder,'checkpoints','Agent1600.mat');hash=checkpointreview.sha256(source);
v=whos('-file',source);name='saved_agent';if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
d=load(source,name);original=d.(name);clear d
candidate=trainingtools.resize_sac_replay(original,500000);
folder=tempname(fullfile(root,'tests','output'));mkdir(folder);file=fullfile(folder,'grown.mat');
saved_agent=candidate;save(file,'saved_agent','-v7');clear saved_agent
r=trainingtools.audit_sac_replay_retention(source,file);
assert(r.source_prefix_retained && r.source_length==50000 && r.candidate_length==50000 && r.candidate_capacity==500000);
data=getLastNData(original.ExperienceBuffer,50000);data(1).Reward=data(1).Reward+123;
for k=1:6,append(candidate.ExperienceBuffer,data);end
saved_agent=candidate;save(file,'saved_agent','-v7');clear saved_agent
r=trainingtools.audit_sac_replay_retention(source,file);
assert(r.source_prefix_retained && r.candidate_length==350000);
base=trainingtools.resize_sac_replay(original,50000);append(base.ExperienceBuffer,data);
saved_agent=base;save(fullfile(folder,'replaced.mat'),'saved_agent','-v7');clear saved_agent
r=trainingtools.audit_sac_replay_retention(source,fullfile(folder,'replaced.mat'));
assert(~r.source_prefix_retained && r.candidate_length==50000);
assert(strcmp(hash,checkpointreview.sha256(source)) && original.ExperienceBuffer.Length==50000);
fprintf('REPLAY_RETENTION_OK: real paper64 state preserved on resize/save; initial 50k retained after 300k synthetic appends; 50k replacement detected. No training/simulation.\n');
end
