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
cfg.diagnosticDir=fullfile(legacy,'diagnostics');
trainingcurriculum.write_json(fullfile(legacy,'control.json'),cfg);
old=retry(resume=legacy,start=false);
assert(strcmp(old.sessionDir,legacy));
assert(strcmp(old.diagnosticDir,cfg.diagnosticDir));
fprintf('PASS: relative curriculum/resume anchored to project; absolute resume preserved; no training.\n');
end

function restore(oldPath,oldFolder)
% 恢復此測試暫改的呼叫者環境，避免 fixture 影響後續測試。
cd(oldFolder); path(oldPath);
end
