function test_sac_serial_recipe()
% Preparation only: defaults, immutable dispatch, snapshot and bounded cap.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
info=trainingtools.prepare_sac_trial();
c=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(strcmp(c.executionMode,'serial') && strcmp(c.trainingDevice,'cpu'));
assert(c.maxAttempts==1 && c.episodesPerProcess==500 && c.checkpointEvery==100);
assert(strcmp(c.fastRestart,'off'));
assert(c.numWorkers==1 && c.minWorkers==1 && isempty(c.fallbackWorkers));
assert(isempty(dir(fullfile(info.sessionDir,'attempt_*'))));
assert(~isfile(fullfile(info.sessionDir,'Agent_Final.mat')));
before=fileread(fullfile(info.sessionDir,'control.json'));
rejected=false;
try,retry(resume=info.sessionDir,executionMode='parallel',start=false);
catch e,rejected=strcmp(e.identifier,'Modular:Immutable');end
assert(rejected && strcmp(before,fileread(fullfile(info.sessionDir,'control.json'))));
rejected=false;
try,retry(resume=info.sessionDir,fastRestart='invalid',start=false);
catch e,rejected=strcmp(e.identifier,'Modular:FastRestart');end
assert(rejected && strcmp(before,fileread(fullfile(info.sessionDir,'control.json'))));
retry(resume=info.sessionDir,maxAttempts=0,fastRestart='off',start=false);
night=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(night.maxAttempts==0 && night.episodesPerProcess==500 && strcmp(night.executionMode,'serial'));
assert(isempty(dir(fullfile(info.sessionDir,'attempt_*'))));
plan=trainingcurriculum.load_plan(fullfile(info.sessionDir,'curriculum.json'),true);
assert(numel(plan.stages)==8 && strcmp(plan.model,'sac_lstm128'));
fprintf('PASS: serial CPU 500-episode fresh recipe, no launch, immutable execution mode.\n');
end
