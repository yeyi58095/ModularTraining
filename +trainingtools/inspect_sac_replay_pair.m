function outDir=inspect_sac_replay_pair(receipt)
% Inspect five preserved checkpoints sequentially; never train or simulate.
arguments
    receipt (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));
p=jsondecode(fileread(receipt));
assert(p.parentEpisode==1100,'SAC:Receipt','Expected parent1100.');
parent=fullfile(p.source,'checkpoints','Agent1100.mat');
assert(strcmp(checkpointreview.sha256(parent),p.parentSHA256),'SAC:Receipt','Parent SHA mismatch.');
runs=string({p.source,p.baseline,p.baseline,p.largerReplay,p.largerReplay});
episodes=[1100 1400 1600 1400 1600];
labels=["parent1100","buffer100k-1400","buffer100k-1600","buffer500k-1400","buffer500k-1600"];
for k=1:numel(runs)
    status=jsondecode(fileread(fullfile(runs(k),'status.json')));
    assert(strcmp(status.state,'paused'),'SAC:Active','All source runs must be paused.');
    assert(isfile(fullfile(runs(k),'checkpoints',sprintf('Agent%d.mat',episodes(k)))));
end
outDir=string(tempname(fullfile(root,'artifacts')));mkdir(outDir);
copyfile(receipt,fullfile(outDir,'pair-receipt.json'));
for k=1:numel(runs)
    fprintf('Inspecting %s (%d/5) ...\n',labels(k),k);
    report=trainingtools.inspect_sac_checkpoint(runs(k),episodes(k));
    file=fullfile(outDir,labels(k)+".json");
    f=fopen(file,'w','n','UTF-8');assert(f>=0,'SAC:Output','Cannot write output.');
    cleanup=onCleanup(@() fclose(f));
    fprintf(f,'%s',jsonencode(report,'PrettyPrint',true));clear cleanup
end
fprintf('Complete. No training or simulation. Reports: %s\n',outDir);
end
