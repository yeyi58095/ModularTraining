function outcome = checkpoint_mark_success(runDir, rewards, targetReward, averageWindow)
% 非課程成功判定：只在尾端完整且有限的 reward 視窗達 targetReward 時發布成功副本。
% 回傳 outcome；不改原 agent 權重，課程模式使用自己的 JSON 過關規則。
% Publish a separate success artifact only after a complete finite reward window.
    validateattributes(averageWindow, {'numeric'}, {'scalar','integer','positive'});
    validateattributes(targetReward, {'numeric'}, {'scalar','finite'});
    rewards = rewards(:);
    tailMean = NaN;
    if numel(rewards) >= averageWindow
        tail = rewards(end-averageWindow+1:end);
        if all(isfinite(tail)), tailMean = mean(tail); end
    end
    achieved = isfinite(tailMean) && tailMean >= targetReward;
    outcome = struct('success',achieved,'episodes',numel(rewards), ...
        'averageReward',tailMean,'finalAgent',fullfile(runDir,'Agent_Final.mat'), ...
        'successAgent','');
    if ~achieved, return; end
    destination = fullfile(runDir, 'Agent_Success.mat');
    assert(~isfile(destination), 'Checkpoint:SuccessExists', ...
        'Refusing to overwrite an existing success artifact.');
    temporary = [tempname(runDir) '.mat'];
    guard = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
    [ok,message] = copyfile(outcome.finalAgent, temporary);
    assert(ok, 'Checkpoint:SuccessCopy', '%s', message);
    [ok,message] = movefile(temporary, destination);
    assert(ok, 'Checkpoint:SuccessPublish', '%s', message);
    outcome.successAgent = destination;
    fprintf('Reward target reached. Success agent saved: %s\n', destination);
end

function removeTemporary(filename)
% 只清理本次尚未發布的暫存 MAT，不刪除正式 checkpoint。
    if isfile(filename), delete(filename); end
end
