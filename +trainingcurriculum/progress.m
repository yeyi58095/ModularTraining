function report = progress(stage,rewards,steps)
% PROGRESS evaluates and describes the same conditions used by decide.
% Histories contain saved stage-local episodes, oldest first.
rewards=rewards(:); steps=steps(:);
assert(numel(rewards)==numel(steps),'Curriculum:History','Reward/step history lengths differ.');
node=evaluate(stage.advance_when,rewards,steps);
report=struct('stageEpisodes',numel(rewards),'passed',node.passed,'tree',node, ...
    'compact',compact(node),'missing',{missing(node)});
% Match decide's no-zero-episode gate even for an at_most episode condition.
if isempty(rewards)
    report.passed=false;
    report.missing=[{'No completed stage episodes'} report.missing];
end
end

function node=evaluate(condition,rewards,steps)
if isfield(condition,'all') || isfield(condition,'any')
    if isfield(condition,'all'), operator='all'; children=condition.all;
    else, operator='any'; children=condition.any; end
    if ~iscell(children), children=num2cell(children); end
    evaluated=cell(size(children)); values=false(size(children));
    for i=1:numel(children)
        evaluated{i}=evaluate(children{i},rewards,steps); values(i)=evaluated{i}.passed;
    end
    if strcmp(operator,'all'), passed=all(values); else, passed=any(values); end
    node=struct('kind','group','operator',operator,'passed',passed,'children',{evaluated});
    return;
end

metric=char(condition.metric); required=[]; current=NaN; met=false; streak=0; needed=1;
window=0; windows=[]; enough=false;
if isfield(condition,'at_least'), comparator='>='; required=condition.at_least;
else, comparator='<='; required=condition.at_most; end
if strcmp(metric,'stage_episodes')
    current=numel(rewards); met=compare(current,comparator,required); enough=true;
else
    window=condition.window;
    if isfield(condition,'consecutive_windows'), needed=condition.consecutive_windows; end
    available=floor(numel(rewards)/window); used=min(available,needed);
    windows=NaN(1,used); windowPass=false(1,used);
    for i=1:used
        last=numel(rewards)-(i-1)*window; first=last-window+1; range=first:last;
        switch metric
            case 'reward_mean', windows(i)=mean(rewards(range));
            case 'steps_mean', windows(i)=mean(steps(range));
            case 'full_length_rate'
                if all(isfinite(steps(range)))
                    windows(i)=mean(steps(range)>=condition.steps_at_least);
                end
            otherwise, error('Curriculum:Invalid','Unknown metric: %s',metric);
        end
        windowPass(i)=isfinite(windows(i)) && compare(windows(i),comparator,required);
    end
    if used>0, current=windows(1); end
    enough=available>=needed;
    for i=1:used
        if windowPass(i), streak=streak+1; else, break; end
    end
    met=enough && streak>=needed;
end
node=struct('kind','metric','metric',metric,'passed',met,'current',current, ...
    'comparator',comparator,'required',required,'window',window, ...
    'neededWindows',needed,'availableWindows',floor(numel(rewards)/max(1,window)), ...
    'streak',streak,'enoughData',enough,'windowValues',windows);
if isfield(condition,'steps_at_least'), node.stepsAtLeast=condition.steps_at_least; end
end

function yes=compare(value,operator,threshold)
if strcmp(operator,'>='), yes=isfinite(value) && value>=threshold;
else, yes=isfinite(value) && value<=threshold; end
end

function value=compact(node)
if strcmp(node.kind,'group')
    children=cellfun(@compact,node.children,'UniformOutput',false);
    value=sprintf('%s{%s}',node.operator,strjoin(children,'; '));
    if ~node.passed, value=['!' value]; end
    return;
end
mark='PASS'; if ~node.passed, mark='WAIT'; end
if isfinite(node.current), current=sprintf('%.2f',node.current); else, current='unavailable'; end
name=node.metric;
if strcmp(node.metric,'full_length_rate')
    name=sprintf('%s(steps>=%g)',name,node.stepsAtLeast);
    if isfinite(node.current), current=sprintf('%.1f%%',100*node.current); end
    threshold=sprintf('%g%%',100*node.required);
else
    threshold=sprintf('%g',node.required);
end
value=sprintf('%s %s %s %s [%s]',name,current,node.comparator,threshold,mark);
if node.window>0
    value=sprintf('%s; streak %d/%d x %d ep',value,node.streak,node.neededWindows,node.window);
end
end

function items=missing(node)
if node.passed, items={}; return; end
if strcmp(node.kind,'metric')
    gap=node.required-node.current;
    if strcmp(node.comparator,'<='), gap=-gap; end
    if strcmp(node.metric,'stage_episodes')
        items={sprintf('stage_episodes %g %s %g; gap %g',node.current,node.comparator,node.required,max(0,gap))};
    elseif ~node.enoughData
        items={sprintf('%s requires %d complete windows x %d episodes (available %d)', ...
            node.metric,node.neededWindows,node.window,node.availableWindows)};
    else
        items={sprintf('%s: streak %d/%d; latest gap %g (NaN = missing data)', ...
            node.metric,node.streak,node.neededWindows,max(0,gap))};
    end
    return;
end
childItems=cell(size(node.children));
for i=1:numel(node.children), childItems{i}=missing(node.children{i}); end
if strcmp(node.operator,'all')
    items={}; for i=1:numel(childItems), items=[items childItems{i}]; end %#ok<AGROW>
else
    alternatives=cellfun(@(x)strjoin(x,' + '),childItems,'UniformOutput',false);
    items={['以下任一條件組合須達標：' strjoin(alternatives,' 或 ')]};
end
end
