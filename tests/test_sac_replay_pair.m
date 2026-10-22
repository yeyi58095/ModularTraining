function test_sac_replay_pair()
% Prepare two children from a prior two-episode flight fixture; no launch.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','sac-flight-latest.json')));
source=receipt.sessionDir;
files={'control.json','status.json','curriculum.json','model.json','checkpoints/Agent2.mat'};
hashes=cellfun(@(f) checkpointreview.sha256(fullfile(source,f)),files,'UniformOutput',false);
pair=trainingtools.prepare_sac_replay_pair(source,2);
paths={pair.baseline,pair.largerReplay};capacities=[100000 500000];
for k=1:2
    p=paths{k};c=jsondecode(fileread(fullfile(p,'control.json')));
    assert(strcmp(c.executionMode,'serial') && c.maxAttempts==1 && c.episodesPerProcess==500);
    assert(isfile(fullfile(p,'STOP')) && isempty(dir(fullfile(p,'attempt_*'))));
    s=load(fullfile(p,'checkpoints','Agent2.mat'),'Agent_Stage2');
    spec=jsondecode(fileread(fullfile(p,'model.json')));
    trainingmodels.validate_agent(s.Agent_Stage2,spec);
    assert(s.Agent_Stage2.ExperienceBuffer.MaxLength==capacities(k));
    [~,ep]=checkpoint_resume_state(fullfile(p,'checkpoints','Agent2.mat'));assert(ep==2);
    r=jsondecode(fileread(fullfile(p,'recovery.json')));assert(r.parent_episode==2);
end
for k=1:numel(files),assert(strcmp(hashes{k},checkpointreview.sha256(fullfile(source,files{k}))));end
fprintf('PASS: two saved SAC children, capacity100k/500k, same parent history, no launch, parent unchanged.\n');
end
