function test_retry_relative_paths()
% 相對路徑測試：從專案外呼叫 start=false，確認課程解析到專案及舊 run 原位續訓。
% 恢復呼叫前路徑與目錄，不啟動訓練或 pool。
% Regression: launch from outside the project without training or a pool.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; oldFolder=pwd;
guard=onCleanup(@() restore(oldPath,oldFolder)); %#ok<NASGU>
addpath(root);
cd(tempdir);
info=retry(curriculum='curricula/fixed_to_random.json',device='cpu',start=false);
assert(isempty(info.supervisor));
assert(strcmp(fileparts(info.sessionDir),fullfile(root,'experiments','fixed_to_random','runs')));
saved=jsondecode(fileread(fullfile(info.sessionDir,'curriculum.json')));
assert(strcmp(saved.model,'ppo_lstm128'));
session=char(info.sessionDir);
relative=session(numel(root)+2:end);
resumed=retry(resume=relative,start=false);
assert(strcmp(info.sessionDir,resumed.sessionDir));
absolute=retry(resume=info.sessionDir,start=false);
assert(strcmp(info.sessionDir,absolute.sessionDir));
% Copy this inactive fixture into the old layout; resume must preserve its location.
legacyRoot=fullfile(root,'+trainingmodels','ppo_lstm128','runs');
if ~isfolder(legacyRoot), mkdir(legacyRoot); end
legacy=tempname(legacyRoot); copyfile(info.sessionDir,legacy);
cfg=jsondecode(fileread(fullfile(legacy,'control.json')));
sourceDiagnostics=cfg.diagnosticDir;
cfg.diagnosticRoot=fileparts(sourceDiagnostics);
trainingcurriculum.write_json(fullfile(legacy,'control.json'),cfg);
old=retry(resume=legacy,start=false);
assert(strcmp(old.sessionDir,legacy));
assert(strcmp(old.diagnosticDir,fullfile(legacy,'diagnostics')));
assert(~strcmp(old.diagnosticDir,sourceDiagnostics));
relocated=jsondecode(fileread(fullfile(legacy,'control.json')));
assert(~isfield(relocated,'diagnosticRoot'));
entries=dir(fullfile(legacy,'control_history','*.json'));
assert(numel(entries)>0);
previousFound=false;
for k=1:numel(entries)
    previous=jsondecode(fileread(fullfile(entries(k).folder,entries(k).name)));
    previousFound=previousFound || (isfield(previous,'diagnosticRoot') && strcmp(previous.diagnosticDir,sourceDiagnostics));
end
assert(previousFound);
if ispc
    otherVolume='Z:';
    if startsWith(root,otherVolume,IgnoreCase=true), otherVolume='Y:'; end
    foreign=[otherVolume '\ModularTrainingPathFixture\session'];
    rejected=false;
    try, retry(resume=foreign,start=false); catch e, rejected=strcmp(e.identifier,'Workspace:ForeignVolume'); end
    assert(rejected,'Retry must reject a run on another volume.');
    addpath(fullfile(root,'runtime'));
    attemptPath=fullfile(legacy,'stale_attempt_fixture.json');
    trainingcurriculum.write_json(attemptPath,struct('sessionDir',foreign));
    rejected=false;
    try, checkpoint_attempt(attemptPath); catch e, rejected=strcmp(e.identifier,'Workspace:ForeignVolume'); end
    assert(rejected,'An old attempt config must reject a run on another volume.');
end
fprintf('PASS: relative and relocated run paths, saved prior control and foreign-volume refusal. No training.\n');
end

function restore(oldPath,oldFolder)
% 恢復此測試暫改的呼叫者環境，避免 fixture 影響後續測試。
cd(oldFolder); path(oldPath);
end
