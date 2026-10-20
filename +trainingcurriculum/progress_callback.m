function stop = progress_callback(stats,stage,stageIndex,stageCount,stageStartEpisode,stopEpisode,checkpointEvery,guardRules)
% Stream a parser-compatible episode row with provisional stage progress.
% Request normal return at the process cap or an actionable checkpoint boundary.
if nargin<7,checkpointEvery=Inf;end
if nargin<8,guardRules=[];end
stop=false;
try
    episodeIndex=column(stats,'EpisodeIndex');
    rewards=column(stats,'EpisodeReward'); steps=column(stats,'EpisodeSteps');
    if isempty(episodeIndex), error('Curriculum:Progress','EpisodeIndex is unavailable.'); end
    n=min([numel(episodeIndex),numel(rewards),numel(steps)]);
    episodeIndex=episodeIndex(1:n); rewards=rewards(1:n); steps=steps(1:n);
    currentEpisode=episodeIndex(end);
    local=episodeIndex>stageStartEpisode & episodeIndex<=currentEpisode;
    average=lastValue(stats,'AverageReward',NaN);
    totalSteps=lastValue(stats,'TotalAgentSteps',NaN);
    q0=lastValue(stats,'EpisodeQ0',NaN);
    try
        % Retain episode positions if a callback ever supplies sparse history.
        r=NaN(currentEpisode-stageStartEpisode,1); s=r;
        positions=episodeIndex(local)-stageStartEpisode;
        r(positions)=rewards(local); s(positions)=steps(local);
        progress=trainingcurriculum.progress(stage,r,s);
        detail=progress.compact;
    catch err
        detail=['progress unavailable: ' regexprep(err.message,'[\r\n]+',' ')];
    end
    suffix=sprintf(' | Stage %d/%d %s | provisional as of Ep %d: stage episodes %d/%d; %s', ...
        stageIndex,stageCount,char(stage.id),currentEpisode,currentEpisode-stageStartEpisode,stage.max_episodes,detail);
    fprintf('Episode: %d/%d | Episode reward: %8.2f | Episode steps: %d | Average reward: %8.2f | Step Count: %d | Episode Q0: %8.2f%s\n', ...
        currentEpisode,stopEpisode,rewards(end),steps(end),average,round(totalSteps),q0,suffix);
catch err
    % Logging is best-effort; preserve the original max-episode stop boundary.
    try
        fprintf('Curriculum live progress unavailable at episode callback: %s\n',err.message);
    catch
    end
end
try
    indices=column(stats,'EpisodeIndex');
    if ~isempty(indices), stop=indices(end)>=stopEpisode; end
    if ~stop && ~isempty(indices) && mod(indices(end),checkpointEvery)==0
        % This only requests normal train return. The engine saves Agent_Final
        % first, then makes the authoritative guard/curriculum decision.
        rewards=column(stats,'EpisodeReward'); steps=column(stats,'EpisodeSteps');
        assert(isequal(indices(:),(1:indices(end))') && ...
            numel(rewards)==numel(indices) && numel(steps)==numel(indices), ...
            'Curriculum:CallbackHistory','Boundary decision requires contiguous full history.');
        decision=trainingcurriculum.decide(stage,rewards(stageStartEpisode+1:end),steps(stageStartEpisode+1:end));
        stop=~strcmp(decision.action,'continue');
        if ~isempty(guardRules)
            assessment=trainingguard.assess(rewards,steps,stageStartEpisode,guardRules);
            regressionPause=~isfield(guardRules,'regression_action') || strcmp(guardRules.regression_action,'pause');
            budgetEnabled=~isfield(guardRules,'budget_enabled') || guardRules.budget_enabled;
            stop=stop || (regressionPause && assessment.suspected_regression) || ...
                (budgetEnabled && indices(end)>=guardRules.origin_episode+guardRules.max_additional_episodes);
        end
        if stop, fprintf('Boundary stop requested at episode %d; save and formal decision follow.\n',indices(end)); end
    end
catch err
    % Stop normally and save for diagnosis rather than silently ignoring a guard.
    stop=true;
    warning('Curriculum:BoundaryCheck','Boundary check failed; saving and stopping: %s',err.message);
end
end

function values=column(source,name)
if isstruct(source) && isfield(source,name), values=source.(name)(:);
else, values=[]; end
end

function value=lastValue(source,name,fallback)
values=column(source,name);
if isempty(values), value=fallback; else, value=values(end); end
end
