function test_short_run_paths()
% 短路徑保存測試：合成長 run 名稱，驗證短段落目錄的 v7.3 保存／讀回與路徑上限保護。
% 會寫入 tests/output 的測試 MAT，不執行 train。
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'runtime'));
output=fullfile(root,'tests','output'); if ~isfolder(output), mkdir(output); end
base=tempname(output); mkdir(base);
session=fullfile(base,repmat('x',1,200-numel(base)-1)); mkdir(session);
assert(numel(session)==200);
% Mimic the previous nested timestamp + UUID layout with a v7.3 save.
old=fullfile(session,'runs','20260923_234055_tp93ee1746_b79c_4ec8_b229_ddd85c9f88d0');
mkdir(old); value=42;
try
    save(fullfile(old,'TrainingOptions.mat'),'value','-v7.3');
    fprintf('Old long path supported on this host (%d characters).\n',numel(fullfile(old,'TrainingOptions.mat')));
catch err
    fprintf('Reproduced old long-path save failure (%d characters): %s\n', ...
        numel(fullfile(old,'TrainingOptions.mat')),err.message);
end
folder=checkpoint_run_log_dir(session);
optionsForDisk=rlTrainingOptions('MaxEpisodes',1,'UseParallel',true);
save(fullfile(folder,'TrainingOptions.mat'),'optionsForDisk','-v7.3');
loaded=load(fullfile(folder,'TrainingOptions.mat'));
assert(loaded.optionsForDisk.MaxEpisodes==1);
next=checkpoint_run_log_dir(session);
assert(~strcmp(folder,next));
assert(isfile(fullfile(folder,'TrainingOptions.mat')));
tooLong=fullfile(session,repmat('y',1,50)); mkdir(tooLong);
rejected=false;
try, checkpoint_run_log_dir(tooLong); catch err, rejected=strcmp(err.identifier,'Checkpoint:PathTooLong'); end
assert(rejected);
fprintf('PASS: short v7.3 options save/load, distinct attempt folders, long-path guard.\n');
fprintf('Test artifacts: %s\n',base);
end
