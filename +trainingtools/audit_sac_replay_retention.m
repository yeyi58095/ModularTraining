function report=audit_sac_replay_retention(sourceFile,candidateFile)
% Read immutable model files. Content equality of oldest chronological prefix.
sourceHash=checkpointreview.sha256(sourceFile);candidateHash=checkpointreview.sha256(candidateFile);
a=loadAgent(sourceFile);b=loadAgent(candidateFile);
[x,~]=getLastNData(a.ExperienceBuffer,a.ExperienceBuffer.Length);
[y,~]=getLastNData(b.ExperienceBuffer,b.ExperienceBuffer.Length);
retained=numel(y)>=numel(x) && isequaln(x(:),reshape(y(1:numel(x)),[],1));
report=struct('source_file',char(sourceFile),'candidate_file',char(candidateFile), ...
    'source_sha256',sourceHash,'candidate_sha256',candidateHash, ...
    'source_length',a.ExperienceBuffer.Length,'candidate_length',b.ExperienceBuffer.Length, ...
    'source_capacity',a.ExperienceBuffer.MaxLength,'candidate_capacity',b.ExperienceBuffer.MaxLength, ...
    'source_prefix_retained',retained, ...
    'scope','Exact chronological transition content equality. False does not prove zero overlap; true does not measure sampling frequency or establish causal retention benefit.');
assert(strcmp(sourceHash,checkpointreview.sha256(sourceFile)) && strcmp(candidateHash,checkpointreview.sha256(candidateFile)), ...
    'ReplayAudit:Changed','Source changed during read-only audit.');
report.files_unchanged=true;
end
function agent=loadAgent(file)
v=whos('-file',file);name='saved_agent';if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
d=load(file,name);agent=d.(name);assert(isa(agent,'rl.agent.rlSACAgent'));
end
