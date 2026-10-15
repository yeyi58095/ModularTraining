function test_environment_versions()
% No pool, sim or train. Covers real launcher, immutable snapshots and attempt wiring.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
info=retry(environment="spatial_v1",start=false,device="cpu");
[model,manifest]=trainingenv.resolve(info.sessionDir);
assert(strcmp(manifest.id,'spatial_v1') && isfile(model));
retry(resume=info.sessionDir,start=false);
reject(@()retry(resume=info.sessionDir,environment="spatial_v1",start=false),'Environment:Immutable');
reject(@()retry(environment="../runtime",start=false),'Environment:Id');
reject(@()retry(environment="not_registered",start=false),'Environment:Unknown');
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);
% Moving/copying a stopped run's environment needs no absolute-path rewrite.
copyfile(fullfile(info.sessionDir,'environment'),fullfile(fixture,'environment'));
copyfile(fullfile(info.sessionDir,'environment.json'),fullfile(fixture,'environment.json'));
[relocated,~]=trainingenv.resolve(fixture);
assert(strcmp(checkpointreview.sha256(relocated),checkpointreview.sha256(model)));
fid=fopen(relocated,'a');fprintf(fid,'tampered');fclose(fid);
reject(@()trainingenv.resolve(fixture),'Environment:HashMismatch');
bad=manifest;bad.files(1).name='../FAFA_Simulation.slx';
trainingcurriculum.write_json(fullfile(fixture,'bad.json'),bad);
reject(@()trainingenv.verify(fullfile(fixture,'bad.json'),fixture),'Environment:Path');
empty=fullfile(fixture,'unbound');mkdir(empty);
reject(@()trainingenv.resolve(empty),'Environment:Unbound');
copyfile(fullfile(info.sessionDir,'model.json'),empty);
copyfile(fullfile(info.sessionDir,'control.json'),empty);
copyfile(fullfile(info.sessionDir,'model_source'),fullfile(empty,'model_source'));
before=checkpointreview.sha256(fullfile(empty,'control.json'));
reject(@()retry(resume=empty,start=false),'Environment:Unbound');
assert(strcmp(before,checkpointreview.sha256(fullfile(empty,'control.json'))));
% Schema v1 remains readable; schema v2 pins an environment and round-trips.
p=trainingcurriculum.load_plan(fullfile(root,'curricula','fixed_to_random.json'),true);
p.schema_version=2;p.environment='spatial_v1';
planFile=fullfile(fixture,'curriculum.json');trainingcurriculum.write_json(planFile,p);
fresh=retry(curriculum=planFile,start=false,device="cpu");
reject(@()retry(curriculum=planFile,environment="wrong",start=false),'Environment:Mismatch');
% Actual attempt dispatch to a private fake engine must pass the run SLX.
mock=fullfile(fixture,'mock');mkdir(mock);
fid=fopen(fullfile(mock,'training_engine.m'),'w');
fprintf(fid,'%s\n','assert(isfile(checkpointOverrides.environmentModelFile));', ...
    'assert(contains(checkpointOverrides.environmentModelFile,[filesep ''environment'' filesep]));', ...
    'successSummary=struct(''success'',false,''episodes'',1,''averageReward'',0);');fclose(fid);
cfg=jsondecode(fileread(fullfile(fresh.sessionDir,'control.json')));
cfg.scriptDir=mock;cfg.attempt=1;cfg.resumeCandidates={};cfg.attemptDir=fullfile(fixture,'attempt');mkdir(cfg.attemptDir);
config=fullfile(fixture,'attempt.json');trainingcurriculum.write_json(config,cfg);
checkpoint_attempt(config);
assert(isfile(fullfile(cfg.attemptDir,'result.json')));
assert(isfile(fullfile(cfg.attemptDir,'environment_used.json')));
% Load the real snapshot by absolute path without a simulation.
assert(~bdIsLoaded('FAFA_Simulation'));
oldFolder=pwd;folderGuard=onCleanup(@()cd(oldFolder)); %#ok<NASGU>
cd(fileparts(model));
load_system(model);assert(strcmpi(get_param('FAFA_Simulation','FileName'),model));close_system('FAFA_Simulation',0);
fprintf('PASS environment versions: prepare/resume, moved snapshot, tamper, traversal, schema and attempt binding.\n');
end
function reject(f,id)
try,f();catch err,assert(strcmp(err.identifier,id),'Unexpected: %s',err.message);return;end
error('Test:ExpectedFailure','Expected %s',id);
end
