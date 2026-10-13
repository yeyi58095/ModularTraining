function test_curriculum_end_to_end()
% 真實三階段短測：固定→MAT→random 各一回合，CPU／1 worker，確認階段間 actor／critic 權重接續。
% 明確執行才啟動訓練；僅驗證接線與保存，不代表長期收斂或多 worker 驗證。
% REAL UAV training: 3 episodes, 1 CPU worker, 3 fresh MATLAB attempts.
% Explicit invocation only. Episode-count gates test wiring, not learning.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root,fullfile(root,'runtime'));
output=fullfile(root,'tests','output'); if ~isfolder(output), mkdir(output); end
fixture=tempname(output); mkdir(fixture);
s=(0:1.5:6000)';
waypoints=[50+s,zeros(size(s)),70*ones(size(s))];
velocity=repmat([15 0 0],numel(s),1);
save(fullfile(fixture,'straight.mat'),'waypoints','velocity');
plan=trainingcurriculum.load_plan(fullfile(root,'curricula','fixed_to_random.json'),true);
base=plan.stages{1};
base.advance_when=struct('metric','stage_episodes','at_least',1);
base.max_episodes=1; base.on_limit='pause';
base.wind=struct('east_mps',[0 0],'north_mps',[0 0],'turbulence',[0 0]);
fixed=base; fixed.id='smoke_fixed';
mat=base; mat.id='smoke_mat';
mat.trajectory=struct('type','mat','file','straight.mat', ...
    'waypoints_variable','waypoints','velocity_variable','velocity');
random=base; random.id='smoke_random';
random.trajectory=struct('type','random','refresh_every_worker_episodes',10);
plan.stages={fixed,mat,random};
planFile=fullfile(fixture,'smoke.json'); trainingcurriculum.write_json(planFile,plan);
info=retry(curriculum=planFile,workers=1,minWorkers=1,fallbackWorkers=[],device="cpu", ...
    checkpointEvery=1,episodesPerProcess=1,averageWindow=1,maxAttempts=3, ...
    maxNoProgressFailures=1,retryDelaySeconds=1,startupTimeoutSeconds=300, ...
    stallTimeoutSeconds=600,start=false);
receipt=struct('sessionDir',info.sessionDir,'status','running','purpose','three real episodes; not convergence');
receiptFile=fullfile(output,'curriculum-smoke-latest.json'); trainingcurriculum.write_json(receiptFile,receipt);
timer=tic;
cmd=sprintf('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" -ConfigFile "%s"', ...
    fullfile(root,'runtime','checkpoint_supervisor.ps1'),fullfile(info.sessionDir,'control.json'));
[exitCode,console]=system(cmd); fprintf('%s',console);
state=jsondecode(fileread(fullfile(info.sessionDir,'status.json')));
receipt.durationSeconds=toc(timer); receipt.supervisorState=state.state;
receipt.status='failed'; trainingcurriculum.write_json(receiptFile,receipt);
assert(exitCode==0 && strcmp(state.state,'success'),'Smoke:Failed', ...
    'Real curriculum smoke failed: %s. Inspect %s',state.message,info.sessionDir);
[history,episode]=checkpoint_resume_state(fullfile(info.sessionDir,'Agent_Success.mat'));
assert(episode==3 && all(isfinite(history.EpisodeReward)));
stage=jsondecode(fileread(fullfile(info.sessionDir,'curriculum_state.json')));
assert(stage.stage_index==3 && stage.start_episode==2 && numel(stage.completed)==2);
for i=1:3
    result=jsondecode(fileread(fullfile(info.sessionDir,sprintf('attempt_%05d',i),'result.json')));
    ready=jsondecode(fileread(fullfile(info.sessionDir,sprintf('attempt_%05d',i),'pool_ready.json')));
    assert(result.stageIndex==i && result.episodes==i && ready.actualWorkers==1);
    if i>1, assert(~isempty(result.resumeFile),'Smoke:Resume','Stage did not resume a checkpoint.'); end
end
% Prove the next stage starts from exactly the previous saved network weights.
for i=1:2
    prior=load(fullfile(info.sessionDir,'runs',sprintf('r%06d',i),'Agent_Final.mat'),'Agent_Stage2');
    next=load(fullfile(info.sessionDir,'runs',sprintf('r%06d',i+1),'Agent_Initial.mat'),'Agent_Stage2');
    assert(isequaln(getLearnableParameters(getActor(prior.Agent_Stage2)), ...
        getLearnableParameters(getActor(next.Agent_Stage2))),'Smoke:ActorReset','Actor weights reset at transition.');
    assert(isequaln(getLearnableParameters(getCritic(prior.Agent_Stage2)), ...
        getLearnableParameters(getCritic(next.Agent_Stage2))),'Smoke:CriticReset','Critic weights reset at transition.');
end
workers=readtable(fullfile(info.diagnosticDir,'episode_workers.csv'));
assert(isequal(workers.Episode(:),(1:3)') && all(workers.ActualWorkers==1));
receipt.status='passed'; receipt.episodes=episode;
receipt.rewards=history.EpisodeReward; receipt.steps=history.EpisodeSteps;
receipt.weightsPreservedAcrossStages=true;
trainingcurriculum.write_json(receiptFile,receipt);
fprintf('PASS: REAL fixed -> MAT -> random, checkpoint resume, preserved actor/critic, three episodes, one CPU worker.\n');
fprintf('Duration %.1f seconds. Receipt: %s\n',receipt.durationSeconds,receiptFile);
end
