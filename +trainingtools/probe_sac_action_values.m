function out=probe_sac_action_values(sessionDir,inputFile,episodes)
% MLP-only bounded Q action curves on 16 identical stored observations.
arguments
    sessionDir (1,1) string
    inputFile (1,1) string
    episodes (1,:) double {mustBePositive,mustBeInteger} = [2100 2200 2500]
end
root=fileparts(fileparts(mfilename('fullpath')));
assert(java.io.File(char(sessionDir)).isAbsolute());
assert(~isempty(episodes) && numel(unique(episodes))==numel(episodes));
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
guard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));assert(strcmp(status.state,'paused'));
spec=jsondecode(fileread(fullfile(sessionDir,'model.json')));
assert(strcmp(spec.name,'sac_mlp128') && spec.lstmUnits==0);
d=load(inputFile,'sequences','sources');e=d.sequences{1};
assert(strcmpi(checkpointreview.sha256(d.sources{1}.file),d.sources{1}.sha256));
assert(strcmpi(char(java.io.File(d.sources{1}.file).getCanonicalPath()), ...
    char(java.io.File(char(fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',episodes(1))))).getCanonicalPath())));
indices=unique(round(linspace(min(65,numel(e)),numel(e),16)));
grid=linspace(-1,1,33);
out=string(tempname(fullfile(root,'artifacts')));mkdir(out);
for ep=episodes
    fprintf('Action-value probe Episode%d: %d observations x33 actions.\n',ep,numel(indices));
    file=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep));hash=checkpointreview.sha256(file);
    v=whos('-file',file);name='saved_agent';if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
    loaded=load(file,name);agent=loaded.(name);clear loaded
    actor=getActor(agent);critics=getCritic(agent);actor.UseDevice='cpu';
    aw=getLearnableParameters(actor);cw=cell(1,numel(critics));
    for k=1:numel(critics),critics(k).UseDevice='cpu';cw{k}=getLearnableParameters(critics(k));end
    q=zeros(numel(indices),numel(grid),numel(critics));mu=zeros(numel(indices),1);sigma=mu;recorded=mu;
    for i=1:numel(indices)
        item=e(indices(i));p=evaluate(actor,item.Observation);
        mu(i)=scalar(p{1});sigma(i)=scalar(p{2});recorded(i)=scalar(item.Action{1});
        for j=1:numel(grid)
            for k=1:numel(critics)
                q(i,j,k)=scalar(getValue(critics(k),item.Observation,{grid(j)}));
            end
        end
    end
    assert(all(isfinite([q(:);mu;sigma;recorded])));
    assert(isequaln(aw,getLearnableParameters(actor)));
    for k=1:numel(critics),assert(isequaln(cw{k},getLearnableParameters(critics(k))));end
    assert(strcmp(hash,checkpointreview.sha256(file)));
    report=struct('status','complete','source',char(file),'sha256',hash, ...
        'input_sha256',checkpointreview.sha256(inputFile),'sequence_source',d.sources{1}, ...
        'indices',indices,'action_grid',grid,'q_values',q,'recorded_actions',recorded, ...
        'gaussian_mean',mu,'gaussian_std',sigma,'weights_unchanged',true,'source_unchanged',true, ...
        'scope','Off-policy critic action curves; Gaussian outputs pre-transform. Not true returns, TD error, or proof of overestimation.');
    trainingcurriculum.write_json(fullfile(out,sprintf('episode%d.json',ep)),report);
    clear agent actor critics
end
fprintf('Complete. No training or simulation. Reports: %s\n',out);
end
function value=scalar(value)
if isa(value,'dlarray'),value=extractdata(value);end
value=double(gather(value));assert(isscalar(value));
end
