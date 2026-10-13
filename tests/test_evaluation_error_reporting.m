function test_evaluation_error_reporting()
% 評估錯誤保存測試：在隔離 fixture 注入模型載入錯誤並移除 root path。
% 確認原始錯誤與堆疊不被報告寫入失敗遮蓋；此測試不啟動模擬。
% Exercise the actual evaluator catch after loss of its package search path.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; cleanup=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root);
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
fixture=tempname(fullfile(root,'tests','output')); mkdir(fixture);
fid=fopen(fullfile(fixture,'load_system.m'),'w');
fprintf(fid,'function load_system(varargin)\nrmpath(''%s'');\nerror(''Test:OriginalModelFailure'',''Injected failure after removing project path'');\nend\n',strrep(root,'''',''''''));
fclose(fid);
addpath(fixture,'-begin');
try
    compare_training_checkpoints(receipt.sessionDir,episodes=1,includeLatest=false,stages=1,maxSteps=5);
    error('Test:MissingRethrow','Expected original exception.');
catch actual
    assert(strcmp(actual.identifier,'Test:OriginalModelFailure'),'%s',getReport(actual));
    assert(strcmp(actual.stack(1).name,'load_system'));
end
files=dir(fullfile(receipt.sessionDir,'reports','evaluation_*','evaluation.json'));
[~,order]=sort([files.datenum],'descend');
saved=jsondecode(fileread(fullfile(files(order(1)).folder,'evaluation.json')));
assert(strcmp(saved.status,'failed') && strcmp(saved.phase,'load_model'));
assert(strcmp(saved.error.identifier,'Test:OriginalModelFailure'));
assert(~saved.error.project_on_path);
assert(contains(saved.error.report,'Injected failure'));
fprintf('PASS evaluator preserves original error and saves report after package path removal. No simulation started.\n');
end
