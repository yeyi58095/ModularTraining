function result = preflight_round3()
% Third experiment group: inspect fresh-agent settings; no run, agent, pool or training.
root=fileparts(fileparts(mfilename('fullpath')));
old=path; cleanup=onCleanup(@()path(old)); %#ok<NASGU>
addpath(root,'-begin');
configFile=fullfile(root,'configs','lab_gpu6_progressive_v2.json');
cfg=jsondecode(fileread(configFile));
assert(isfield(cfg,'start') && isequal(cfg.start,false),'Round3:Start','Preparation must have start=false.');
assert(~isfield(cfg,'resume'),'Round3:Resume','Round 3 must start a new agent, not resume.');
assert(strcmp(cfg.curriculum,'experiments/progressive_v2/curriculum.json') && ...
    strcmp(cfg.environment,'spatial_v2'),'Round3:Recipe','Unexpected curriculum or environment.');
planFile=fullfile(root,cfg.curriculum);
plan=trainingcurriculum.load_plan(planFile,true);
assert(numel(plan.stages)==8 && strcmp(plan.model,'ppo_lstm128') && ...
    strcmp(plan.environment,'spatial_v2'),'Round3:Plan','Expected eight-stage spatial_v2 plan.');
[manifestFile,assetDir]=trainingenv.registry(root,'spatial_v2');
manifest=trainingenv.verify(manifestFile,assetDir);
modelFile=fullfile(assetDir,manifest.model_file);
sha=checkpointreview.sha256(modelFile);
assert(strcmpi(sha,'997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557'), ...
    'Round3:Environment','Unexpected spatial_v2 asset bytes.');
result=struct('group',3,'freshAgent',true,'config',cfg,'planFile',planFile, ...
    'curriculumSha256',checkpointreview.sha256(planFile),'environmentSha256',sha, ...
    'model',plan.model,'stages',numel(plan.stages),'runCreated',false,'trainingStarted',false);
disp(result);
fprintf('Preflight only. No run/agent created. Round 3 is not a recovery of the successful model.\n');
end
