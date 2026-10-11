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
% Evidence from terminal observations, not a claim of causal block attribution.
row.terminal_observation7=obs(7,end);
row.terminal_observation3=obs(3,end);
row.observation7_abs_max=max(abs(obs(7,:)));
row.termination_evidence='none';
if done
    d=abs(obs(7,end))>=50/30; roll=abs(obs(3,end))>=1;
    if d && roll, row.termination_evidence='distance_and_roll_thresholds';
    elseif d, row.termination_evidence='distance_threshold';
    elseif roll, row.termination_evidence='roll_threshold';
    else, row.termination_evidence='unknown'; end
end
% Threshold interpretation assumes the reviewed model's d/30 and phi/40
% observations. Raw values and model SHA are retained for version checking.
end
