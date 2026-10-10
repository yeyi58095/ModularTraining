function result=assess(rewards,steps,startEpisode,rule)
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
result=struct('suspected_regression',false,'low_windows',0,'reference_reward',0, ...
    'reference_steps',0,'reference_end_episode',0,'latest_reward',[], ...
    'latest_steps',[],'last_window_end_episode',startEpisode);
for endpoint=startEpisode+rule.window:rule.window:numel(rewards)
    span=endpoint-rule.window+1:endpoint;
    r=mean(rewards(span)); s=mean(steps(span));
    result.latest_reward=r; result.latest_steps=s; result.last_window_end_episode=endpoint;
    eligible=r>=rule.min_reference_reward && s>=rule.min_reference_steps;
    if eligible && r>result.reference_reward
        result.reference_reward=r; result.reference_steps=s;
        result.reference_end_episode=endpoint;
    end
    low=result.reference_end_episode>0 && r<rule.reward_ratio*result.reference_reward && ...
        s<rule.steps_ratio*result.reference_steps;
    if low, result.low_windows=result.low_windows+1; else, result.low_windows=0; end
end
result.suspected_regression=result.low_windows>=rule.patience;
end
