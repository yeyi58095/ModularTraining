function row=summarize(experience,maxSteps)
% Each reward is a transition, including the one labelled t=0 by sim().
values=double(experience.Reward.Data(:));
assert(~isempty(values) && all(isfinite(values)),'Evaluation:Reward','Missing or nonfinite rewards.');
steps=numel(values);
done=any(experience.IsDone.Data(:));
if done, signal='environment_done';
elseif steps>=maxSteps, signal='step_limit';
else, signal='ended_without_done'; end
obsNames=fieldnames(experience.Observation);
obs=double(experience.Observation.(obsNames{1}).Data);
obs=reshape(obs,10,[]);
actionNames=fieldnames(experience.Action);
action=double(experience.Action.(actionNames{1}).Data(:));
row=struct('reward',sum(values),'steps',steps,'reached_step_limit',steps>=maxSteps, ...
    'environment_done',logical(done),'end_signal',signal, ...
    'observation7_rms',sqrt(mean(obs(7,:).^2)), ...
    'action_saturation_fraction',mean(abs(action)>=0.99));
% Channel 7 is intentionally reported in raw observation units, not meters.
end
