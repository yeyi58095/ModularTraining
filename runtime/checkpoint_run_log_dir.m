function folder = checkpoint_run_log_dir(sessionDir)
% 段落日誌目錄：在持有 run 鎖的前提下，建立唯一短名稱 runs/rNNNNNN。
% 回傳 folder；檢查 Windows MAT/HDF5 路徑長度，避免長 UUID 巢狀目錄造成保存失敗。
% A session's supervisor lock serializes attempts. Keep MAT/HDF5 paths short.
root = fullfile(sessionDir,'runs');
if ~isfolder(root), mkdir(root); end
index = 1;
while true
    folder = fullfile(root,sprintf('r%06d',index));
    if ~isfolder(folder) && ~isfile(folder), break; end
    index = index + 1;
end
% Longest filename currently emitted by training_engine.
assert(strlength(string(fullfile(folder,'training_script_snapshot.m'))) < 260, ...
    'Checkpoint:PathTooLong', ...
    'Training output path is too long. Use a shorter project path: %s',folder);
mkdir(folder);
end
