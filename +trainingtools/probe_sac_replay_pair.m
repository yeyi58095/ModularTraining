function outDir=probe_sac_replay_pair(receipt)
% Five frozen agents, identical two episode prefixes, at most256 steps each.
arguments
    receipt (1,1) string
end
assert(strcmp(version('-release'),'2024b'));
root=fileparts(fileparts(mfilename('fullpath')));p=jsondecode(fileread(receipt));
assert(p.parentEpisode==1100);
assert(strcmp(checkpointreview.sha256(fullfile(p.source,'checkpoints','Agent1100.mat')),p.parentSHA256));
runs=string({p.source,p.baseline,p.baseline,p.largerReplay,p.largerReplay});
episodes=[1100 1400 1600 1400 1600];
labels=["parent1100","buffer100k-1400","buffer100k-1600","buffer500k-1400","buffer500k-1600"];
outDir=string(tempname(fullfile(root,'artifacts')));mkdir(outDir);
copyfile(receipt,fullfile(outDir,'pair-receipt.json'));
sequences=cell(1,2);sources=cell(1,2);
for j=1:2
    index=2*j+1;
    [agent,file,hash,guard]=readAgent(runs(index),1600); %#ok<ASGLU>
    b=agent.ExperienceBuffer;
    e=getLastNData(b,min(10000,b.Length));
    terminals=find([e.IsDone]~=0);
    assert(numel(terminals)>=2,'SAC:Sequence','Need two terminal boundaries.');
    first=terminals(end-1)+1;last=terminals(end);
    sequences{j}=e(first:min(last,first+255));
    sources{j}=struct('file',file,'sha256',hash,'complete_episode_steps',last-first+1, ...
        'prefix_steps',numel(sequences{j}),'start_after_terminal',true);
    assert(strcmp(hash,checkpointreview.sha256(file)));
    clear agent b e guard
end
% Exact shared inputs retained for reproducibility; contains at most512 records.
save(fullfile(outDir,'shared-sequences.mat'),'sequences','sources','-v7.3');
for k=1:5
    fprintf('Frozen sequence probe %s (%d/5) ...\n',labels(k),k);
    [agent,file,hash,guard]=readAgent(runs(k),episodes(k)); %#ok<ASGLU>
    report=struct('status','complete','source',file,'sha256',hash,'sequence_sources',{sources});
    report.sequences=cell(1,2);
    for j=1:2
        report.sequences{j}=trainingtools.probe_sac_sequence(agent,sequences{j});
    end
    assert(strcmp(hash,checkpointreview.sha256(file)));
    report.source_unchanged=true;
    trainingcurriculum.write_json(fullfile(outDir,labels(k)+".json"),report);
    clear agent guard
end
fprintf('Complete. No training or simulation. Reports: %s\n',outDir);
end
function [agent,file,hash,guard]=readAgent(run,ep)
lock=System.IO.File.Open(char(fullfile(run,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
guard=onCleanup(@() lock.Dispose());
s=jsondecode(fileread(fullfile(run,'status.json')));assert(strcmp(s.state,'paused'),'SAC:Active','Run must be paused.');
file=fullfile(run,'checkpoints',sprintf('Agent%d.mat',ep));hash=checkpointreview.sha256(file);
v=whos('-file',file);name='saved_agent';if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
d=load(file,name);agent=d.(name);assert(isa(agent,'rl.agent.rlSACAgent'));
end
