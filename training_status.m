function status = training_status(sessionDir,tailLines)
% 顯示指定實驗的狀態與目前 attempt 的 stdout 尾端；只讀、不控制訓練。
% 用法：training_status(info.sessionDir)，或 training_status(info.sessionDir,50)。
arguments
    sessionDir (1,1) string
    tailLines (1,1) double {mustBeInteger,mustBePositive} = 30
end
root=fileparts(mfilename('fullpath'));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
fprintf('Session: %s\n',sessionDir);
status=[];
f=fullfile(sessionDir,'status.json');
if ~isfile(f)
    fprintf('status.json 尚未產生，請確認實驗路徑。\n');return;
end
try
    status=jsondecode(fileread(f));
catch err
    fprintf('暫時無法讀取 status.json；可能正在更新，請稍後重試。\n%s\n',err.message);
    return;
end
disp(status);
if ~isstruct(status) || ~isfield(status,'attempt') || ...
        ~isnumeric(status.attempt) || ~isscalar(status.attempt) || ...
        ~isfinite(status.attempt) || status.attempt<1 || fix(status.attempt)~=status.attempt
    fprintf('目前尚無有效的 attempt 編號。\n');return;
end
f=fullfile(sessionDir,sprintf('attempt_%05d',status.attempt),'stdout.log');
if ~isfile(f)
    fprintf('目前 attempt %d 尚未產生日誌。\n',status.attempt);return;
end
try
    contents=string(fileread(f));
catch err
    fprintf('暫時無法讀取日誌，請稍後重試。\n%s\n',err.message);return;
end
if strlength(strtrim(contents))==0
    fprintf('目前 attempt %d 的日誌仍為空白，尚不能確認新的 episode 已開始。\n',status.attempt);return;
end
lines=splitlines(contents);
if strlength(lines(end))==0,lines(end)=[];end
fprintf('\n=== Attempt %d | latest %d log lines ===\n',status.attempt,tailLines);
disp(join(lines(max(1,numel(lines)-tailLines+1):end),newline));
end
