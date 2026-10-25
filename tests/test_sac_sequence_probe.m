function test_sac_sequence_probe()
% Existing trained synthetic fixture plus synthetic replay, no new learning.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
d=load(fullfile(root,'tests','output','sac-replay-resize.mat'),'candidate');agent=d.candidate;
e=repmat(struct('Observation',{{zeros(10,1)}},'Action',{{0}}, ...
    'Reward',1,'NextObservation',{{zeros(10,1)}},'IsDone',0),240,1);
for k=1:240
    e(k).Observation={ones(10,1)*sin(k/20)*.1};
    e(k).NextObservation={ones(10,1)*sin((k+1)/20)*.1};e(k).IsDone=double(mod(k,80)==0);
end
a=trainingtools.probe_sac_sequence(agent,e(1:80));
b=trainingtools.probe_sac_sequence(agent,e(1:80));
assert(isequaln(a,b) && a.weights_unchanged && size(a.q_recorded_action,2)==2);
assert(isfield(a,'after_burn_in') && a.steps==80);
append(agent.ExperienceBuffer,e);
folder=tempname(fullfile(root,'tests','output'));mkdir(folder);mkdir(fullfile(folder,'checkpoints'));
saved_agent=agent;
for ep=[1100 1400 1600]
    save(fullfile(folder,'checkpoints',sprintf('Agent%d.mat',ep)),'saved_agent','-v7.3');
end
trainingcurriculum.write_json(fullfile(folder,'status.json'),struct('state','paused'));
f=fopen(fullfile(folder,'supervisor.lock'),'w');fclose(f);
p=struct('source',folder,'baseline',folder,'largerReplay',folder,'parentEpisode',1100, ...
    'parentSHA256',checkpointreview.sha256(fullfile(folder,'checkpoints','Agent1100.mat')));
receipt=fullfile(folder,'pair.json');trainingcurriculum.write_json(receipt,p);
out=trainingtools.probe_sac_replay_pair(receipt);
files=dir(fullfile(out,'buffer*.json'));assert(numel(files)==4);
r=jsondecode(fileread(fullfile(out,'parent1100.json')));
assert(r.source_unchanged && r.sequences(1).steps==80);
assert(r.sequence_sources(1).complete_episode_steps==80);
trainingcurriculum.write_json(fullfile(folder,'status.json'),struct('state','running'));
failed=false;try,trainingtools.probe_sac_replay_pair(receipt);catch ex,failed=strcmp(ex.identifier,'SAC:Active');end
assert(failed);
fprintf('PASS: sequential state repeatability, finite Gaussian/Q outputs, weights, shared inputs, five reports, active-run rejection.\n');
end
