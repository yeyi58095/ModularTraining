function test_sac_flight(savedSession,executionMode)
% Two real UAV episodes, CPU/one worker, two stages. NOT a learning benchmark.
if nargin<1,savedSession="";end
if nargin<2,executionMode="parallel";end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
out=fullfile(root,'tests','output');
receiptFile=fullfile(out,'sac-flight-latest.json');
if strlength(savedSession)==0
fixture=tempname(out);mkdir(fixture);
plan=trainingcurriculum.load_plan(fullfile(root,'experiments','sac_spatial_v2','curriculum.json'),true);
stage=plan.stages{3};stage.advance_when=struct('metric','stage_episodes','at_least',1);
stage.max_episodes=500;stage.on_limit='pause';plan.stages={stage,stage};
plan.stages{1}.id='smoke_a';plan.stages{2}.id='smoke_b';
file=fullfile(fixture,'curriculum.json');trainingcurriculum.write_json(file,plan);
info=retry(curriculum=file,environment="spatial_v2",workers=1,minWorkers=1,fallbackWorkers=[], ...
    executionMode=executionMode, ...
    device="cpu",checkpointEvery=1,episodesPerProcess=500,averageWindow=1, ...
    maxAttempts=2,maxNoProgressFailures=1,retryDelaySeconds=1,startupTimeoutSeconds=300, ...
    stallTimeoutSeconds=600,start=false);
receipt=struct('sessionDir',info.sessionDir,'status','running','scope','two CPU flight episodes, not convergence');
trainingcurriculum.write_json(receiptFile,receipt);
cmd=sprintf('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" -ConfigFile "%s"', ...
    fullfile(root,'runtime','checkpoint_supervisor.ps1'),fullfile(info.sessionDir,'control.json'));
[code,console]=system(cmd);fprintf('%s',console);
else
info=struct('sessionDir',char(savedSession));code=0;
receipt=struct('sessionDir',info.sessionDir,'scope','two CPU flight episodes, not convergence');
end
state=jsondecode(fileread(fullfile(info.sessionDir,'status.json')));
assert(code==0 && strcmp(state.state,'success'),'Test:SACFlight','Flight test failed: %s',state.message);
[history,ep]=checkpoint_resume_state(fullfile(info.sessionDir,'Agent_Success.mat'));
assert(ep==2 && all(isfinite(history.EpisodeReward)));
a=load(fullfile(info.sessionDir,'runs','r000001','Agent_Final.mat'),'Agent_Stage2');
b=load(fullfile(info.sessionDir,'runs','r000002','Agent_Initial.mat'),'Agent_Stage2');
assert(isequaln(getLearnableParameters(getActor(a.Agent_Stage2)),getLearnableParameters(getActor(b.Agent_Stage2))));
assert(a.Agent_Stage2.ExperienceBuffer.Length==b.Agent_Stage2.ExperienceBuffer.Length);
% Exercise shared evaluator with two Q critics and unchanged saved weights.
evaluation=compare_training_checkpoints(info.sessionDir,episodes=2,includeLatest=false, ...
    stages=2,seeds=101,maxSteps=5);
assert(evaluation.weights_unchanged);
receipt.status='passed';receipt.episodes=ep;receipt.steps=history.EpisodeSteps;
receipt.evaluation=evaluation.outputDir;receipt.replayPreserved=true;
trainingcurriculum.write_json(receiptFile,receipt);
fprintf('PASS: SAC real spatial_v2 flight, early stage boundary in 500-episode attempt, resume/replay and evaluation.\n');
end
