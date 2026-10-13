function test_end_to_end()
% 真實單回合短測：在新 MATLAB 程序以 CPU／1 worker 驗證成功成果發布。
% 明確執行才啟動訓練；簡易成功門檻是測試接線用途，不代表模型合格。
% One real UAV episode in an isolated fresh MATLAB process, CPU / one worker.
% Deliberately easy success threshold tests artifact publication, not learning.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
info=retry(model="ppo_lstm128",workers=1,fallbackWorkers=[],device="cpu", ...
    checkpointEvery=1,episodesPerProcess=1,averageWindow=1,targetReward=-1e9, ...
    maxAttempts=1,startupTimeoutSeconds=240,stallTimeoutSeconds=240,start=false);
cmd=sprintf('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" -ConfigFile "%s"', ...
    fullfile(root,'runtime','checkpoint_supervisor.ps1'),fullfile(info.sessionDir,'control.json'));
[exitCode,output]=system(cmd); fprintf('%s',output);
assert(exitCode==0,'Supervisor failed. Inspect %s',info.sessionDir);
state=jsondecode(fileread(fullfile(info.sessionDir,'status.json')));
assert(strcmp(state.state,'success'),'Training smoke failed: %s (%s)',state.message,info.sessionDir);
assert(isfile(fullfile(info.sessionDir,'Agent_Success.mat')));
rows=readtable(fullfile(info.diagnosticDir,'episode_workers.csv'));
assert(any(rows.Episode==1 & rows.ActualWorkers==1));
fprintf('PASS: modular entry -> model snapshot -> isolated UAV training -> checkpoint/success -> episode diagnostics.\n');
end
