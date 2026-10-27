function out=probe_sac_mlp_checkpoints(sessionDir,episodes)
% Frozen shared-input comparison, no train/sim or checkpoint mutation.
arguments
    sessionDir (1,1) string
    episodes (1,:) double {mustBePositive,mustBeInteger} = [2100 2200 2500]
end
assert(~isempty(episodes) && numel(unique(episodes))==numel(episodes));
root=fileparts(fileparts(mfilename('fullpath')));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
guard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
s=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(strcmp(s.state,'paused'),'Source must be paused.');
spec=jsondecode(fileread(fullfile(sessionDir,'model.json')));
assert(strcmp(spec.name,'sac_mlp128') && spec.lstmUnits==0,'MLP only.');
out=string(tempname(fullfile(root,'artifacts')));mkdir(out);
sequences=cell(1,2);sources=cell(1,2);
sourceEpisodes=[episodes(1),episodes(end)];
for j=1:2
    [agent,file,hash]=readAgent(sessionDir,sourceEpisodes(j));
    b=agent.ExperienceBuffer;e=getLastNData(b,min(10000,b.Length));
    terminals=find([e.IsDone]~=0);
    assert(numel(terminals)>=2,'Need two terminal boundaries.');
    first=terminals(end-1)+1;last=terminals(end);
    sequences{j}=e(first:min(last,first+255));
    sources{j}=struct('file',char(file),'sha256',hash, ...
        'complete_episode_steps',last-first+1,'prefix_steps',numel(sequences{j}));
    assert(strcmp(hash,checkpointreview.sha256(file)));
    clear agent b e
end
save(fullfile(out,'shared-inputs.mat'),'sequences','sources','-v7');
for ep=episodes
    fprintf('Shared-input probe Episode%d ...\n',ep);
    [agent,file,hash]=readAgent(sessionDir,ep);
    report=struct('status','complete','source',char(file),'sha256',hash, ...
        'sequence_sources',{sources},'sequences',{{}}, ...
        'scope','Identical recorded inputs; Gaussian parameters before action transform and Q on recorded actions, not TD error or rollout.');
    report.sequences=cell(1,2);
    for j=1:2
        report.sequences{j}=trainingtools.probe_sac_sequence(agent,sequences{j});
    end
    assert(strcmp(hash,checkpointreview.sha256(file)));
    report.source_unchanged=true;
    trainingcurriculum.write_json(fullfile(out,sprintf('episode%d.json',ep)),report);
    clear agent
end
fprintf('Complete. No training or simulation. Reports: %s\n',out);
end
function [agent,file,hash]=readAgent(run,ep)
file=fullfile(run,'checkpoints',sprintf('Agent%d.mat',ep));
hash=checkpointreview.sha256(file);
v=whos('-file',file);name='saved_agent';
if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
d=load(file,name);agent=d.(name);assert(isa(agent,'rl.agent.rlSACAgent'));
end
