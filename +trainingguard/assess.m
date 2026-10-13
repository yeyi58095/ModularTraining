function result=assess(rewards,steps,startEpisode,rule)
% 純退步評估：只使用本階段保存歷史的完整、不重疊視窗。
% 合格視窗可更新參考；reward 與 steps 都低於參考比例時累積低分連續數，回傳 assessment 而不改檔。
% Nonoverlapping saved-history windows, isolated to the current stage.
assert(rule.schema_version==1,'Guard:Schema','Unsupported guard schema.');
for key={'window','patience'}
    validateattributes(rule.(key{1}),{'numeric'},{'scalar','integer','positive','finite'});
end
for key={'reward_ratio','steps_ratio'}
    validateattributes(rule.(key{1}),{'numeric'},{'scalar','positive','<=',1,'finite'});
end
for key={'min_reference_reward','min_reference_steps'}
    validateattributes(rule.(key{1}),{'numeric'},{'scalar','positive','finite'});
end
validateattributes(startEpisode,{'numeric'},{'scalar','integer','nonnegative','<=',numel(rewards)});
assert(numel(rewards)==numel(steps) && all(isfinite(rewards)) && all(isfinite(steps)), ...
    'Guard:History','Guard requires matching finite saved reward/step histories.');
% 低分計數與參考窗每次從保存歷史重算；持續暫停旗標由 check.m 保存在 guard_state。
result=struct('suspected_regression',false,'low_windows',0,'reference_reward',0, ...
    'reference_steps',0,'reference_end_episode',0,'latest_reward',[], ...
    'latest_steps',[],'last_window_end_episode',startEpisode);
% 從當階段起點開始切完整視窗，不把前階段或未滿視窗混入。
for endpoint=startEpisode+rule.window:rule.window:numel(rewards)
    span=endpoint-rule.window+1:endpoint;
    r=mean(rewards(span)); s=mean(steps(span));
    result.latest_reward=r; result.latest_steps=s; result.last_window_end_episode=endpoint;
    eligible=r>=rule.min_reference_reward && s>=rule.min_reference_steps;
    % 參考必須 reward／steps 同時達最低門檻，再以較高 reward 選訓練參考窗。
    if eligible && r>result.reference_reward
        result.reference_reward=r; result.reference_steps=s;
        result.reference_end_episode=endpoint;
    end
    % 兩個指標都低於參考比例才算低窗；否則連續計數歸零。
    low=result.reference_end_episode>0 && r<rule.reward_ratio*result.reference_reward && ...
        s<rule.steps_ratio*result.reference_steps;
    if low, result.low_windows=result.low_windows+1; else, result.low_windows=0; end
end
% patience 是連續低分視窗數，而非 episode 數；這是保護規則，不是 PPO 根因判斷。
result.suspected_regression=result.low_windows>=rule.patience;
end
