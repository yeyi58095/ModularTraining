function test_sac_checkpoint_inspection()
% Existing small synthetic fixture; no training or simulation.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
fixture=fullfile(root,'tests','output','sac-replay-resize.mat');
assert(isfile(fixture),'Run the existing resize fixture test first.');
d=load(fixture,'candidate');saved_agent=d.candidate;
folder=tempname(fullfile(root,'tests','output'));mkdir(folder);mkdir(fullfile(folder,'checkpoints'));
save(fullfile(folder,'checkpoints','Agent1.mat'),'saved_agent','-v7.3');
write(fullfile(folder,'status.json'),' {"state":"paused"}');
write(fullfile(folder,'supervisor.lock'),'');
expected=double(gather(getEntropyWeight(saved_agent)));
report=trainingtools.inspect_sac_checkpoint(folder,1);
assert(report.source_unchanged && isequal(report.current_entropy_weight,expected));
assert(report.replay.capacity==640 && report.replay.length==32);
assert(report.replay.sample_count==32 && report.policy_state_saved);
assert(report.networks.Actor{1}.nonfinite==0 && report.networks.Actor{1}.count>0);
encoded=jsonencode(report);assert(~isempty(encoded));
for ep=[1100 1400 1600]
    copyfile(fullfile(folder,'checkpoints','Agent1.mat'), ...
        fullfile(folder,'checkpoints',sprintf('Agent%d.mat',ep)));
end
receipt=struct('source',folder,'baseline',folder,'largerReplay',folder, ...
    'parentEpisode',1100,'parentSHA256',checkpointreview.sha256(fullfile(folder,'checkpoints','Agent1100.mat')));
receiptFile=fullfile(folder,'pair.json');write(receiptFile,jsonencode(receipt));
out=trainingtools.inspect_sac_replay_pair(receiptFile);
assert(numel(dir(fullfile(out,'*.json')))==6);
write(fullfile(folder,'status.json'),' {"state":"running"}');
rejected=false;
try,trainingtools.inspect_sac_checkpoint(folder,1);catch ex,rejected=strcmp(ex.identifier,'SAC:Active');end
assert(rejected,'Active run must be rejected.');
fprintf('PASS: alpha, replay, network summary, source hash and active-run protection.\n');
end
function write(file,value)
f=fopen(file,'w');c=onCleanup(@() fclose(f));fprintf(f,'%s',value);
end
