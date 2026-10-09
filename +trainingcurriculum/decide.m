function decision = decide(stage,rewards,steps)
% Stage-local saved episode data only; no mutable streak counter or eval().
rewards=rewards(:); steps=steps(:);
assert(numel(rewards)==numel(steps),'Curriculum:History','Reward/step history lengths differ.');
passed=~isempty(rewards) && testCondition(stage.advance_when,rewards,steps);
atLimit=numel(rewards)>=stage.max_episodes;
decision=struct('action','continue','reason','conditions_not_met','stage_episodes',numel(rewards));
if passed
    decision.action='advance'; decision.reason='conditions_met';
elseif atLimit
    decision.action=stage.on_limit; decision.reason='episode_budget_reached';
end
end

function result=testCondition(c,rewards,steps)
if isfield(c,'all') || isfield(c,'any')
    isAll=isfield(c,'all');
    if isAll, children=c.all; else, children=c.any; end
    if ~iscell(children), children=num2cell(children); end
    values=false(size(children));
    for i=1:numel(children), values(i)=testCondition(children{i},rewards,steps); end
    if isAll, result=all(values); else, result=any(values); end
    return;
end
if strcmp(c.metric,'stage_episodes')
    values=numel(rewards);
else
    count=1; if isfield(c,'consecutive_windows'), count=c.consecutive_windows; end
    if numel(rewards)<c.window*count, result=false; return; end
    values=zeros(1,count);
    for i=1:count
        last=numel(rewards)-(i-1)*c.window; range=last-c.window+1:last;
        switch c.metric
            case 'reward_mean', values(i)=mean(rewards(range));
            case 'steps_mean', values(i)=mean(steps(range));
            case 'full_length_rate'
                if ~all(isfinite(steps(range))), result=false; return; end
                values(i)=mean(steps(range)>=c.steps_at_least);
        end
    end
end
if ~all(isfinite(values)), result=false;
elseif isfield(c,'at_least'), result=all(values>=c.at_least);
else, result=all(values<=c.at_most); end
end
