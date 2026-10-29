function test_sac_random_flight(savedSession,executionMode,fastRestart,storageVersion)
% Two real UAV episodes, CPU/one worker, two stages. NOT a learning benchmark.
if nargin<1,savedSession="";end
if nargin<2,executionMode="parallel";end
if nargin<3,fastRestart="on";end
if nargin<4,storageVersion="-v7.3";end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
out=fullfile(root,'tests','output');
receiptFile=fullfile(out,'sac-random-flight-latest.json');
if strlength(savedSession)==0
fixture=tempname(out);mkdir(fixture);
plan=trainingcurriculum.load_plan(fullfile(root,'experiments','sac_random_route_v1','curriculum.json'),true);
stage=rmfield(plan.stages{1},'frozen_gate');
stage.advance_when=struct('metric','stage_episodes','at_least',1);
stage.max_episodes=500;stage.on_limit='pause';plan.stages={stage,stage};
plan.stages{1}.id='smoke_a';plan.stages{2}.id='smoke_b';
file=fullfile(fixture,'curriculum.json');trainingcurriculum.write_json(file,plan);
info=retry(curriculum=file,environment="spatial_v2",workers=1,minWorkers=1,fallbackWorkers=[], ...
    executionMode=executionMode,fastRestart=fastRestart, ...
    device="cpu",checkpointEvery=1,episodesPerProcess=500,averageWindow=1, ...
    maxAttempts=2,maxNoProgressFailures=1,retryDelaySeconds=1,startupTimeoutSeconds=300, ...
    stallTimeoutSeconds=600,start=false);
receipt=struct('sessionDir',info.sessionDir,'status','running','scope','two CPU flight episodes, not convergence');
trainingcurriculum.write_json(fullfile(info.sessionDir,'checkpoint_storage.json'), ...
    struct('schema_version',1,'version',char(storageVersion)));
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
if strlength(savedSession)==0 && fastRestart=="off"
    for n=1:2
        log=fileread(fullfile(info.sessionDir,sprintf('attempt_%05d',n),'stdout.log'));
        assert(~contains(log,'Fast Restart mode cannot be enabled'),'Test:FastRestart','Disable option did not reach engine.');
        cfg=jsondecode(fileread(fullfile(info.sessionDir,sprintf('attempt_%05d',n),'attempt.json')));
        assert(strcmp(cfg.fastRestart,'off'));
    end
end
a=load(fullfile(info.sessionDir,'runs','r000001','Agent_Final.mat'),'Agent_Stage2');
if isfile(fullfile(info.sessionDir,'checkpoint_storage.json'))
    storageVersion=string(checkpoint_storage_version(info.sessionDir));
    for filename=[string(fullfile(info.sessionDir,'checkpoints','Agent1.mat')), ...
            string(fullfile(info.sessionDir,'Agent_Final.mat')), ...
            string(fullfile(info.sessionDir,'runs','r000002','Agent_Initial.mat'))]
        fid=fopen(filename,'r');header=fread(fid,20,'*char')';fclose(fid);
        if storageVersion=="-v7",assert(startsWith(header,'MATLAB 5.0 MAT-file'));
        else,assert(startsWith(header,'MATLAB 7.3 MAT-file'));end
    end
end
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
