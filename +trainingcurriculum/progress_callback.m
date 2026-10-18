function stop = progress_callback(stats,stage,stageIndex,stageCount,stageStartEpisode,stopEpisode)
% Stream a parser-compatible episode row with provisional stage progress.
% The custom stop returns true only at the existing MaxEpisodes boundary.
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
catch
    % MaxEpisodes remains a second, native cap if statistics are unavailable.
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
