function status = training_status(sessionDir,tailLines)
% 顯示指定實驗的狀態與目前 attempt 的 stdout 尾端；只讀、不控制訓練。
% 用法：training_status(info.sessionDir)，或 training_status(info.sessionDir,50)。
arguments
    sessionDir (1,1) string
    tailLines (1,1) double {mustBeInteger,mustBePositive} = 30
end
root=fileparts(mfilename('fullpath'));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
fprintf('Session: %s\n',sessionDir);
status=[];
f=fullfile(sessionDir,'status.json');
if ~isfile(f)
    fprintf('status.json 尚未產生，請確認實驗路徑。\n');return;
end
try
    status=jsondecode(fileread(f));
catch err
    fprintf('暫時無法讀取 status.json；可能正在更新，請稍後重試。\n%s\n',err.message);
    return;
end
disp(status);
showCurriculumProgress(sessionDir,status);
if ~isstruct(status) || ~isfield(status,'attempt') || ...
        ~isnumeric(status.attempt) || ~isscalar(status.attempt) || ...
        ~isfinite(status.attempt) || status.attempt<1 || fix(status.attempt)~=status.attempt
    fprintf('目前尚無有效的 attempt 編號。\n');return;
end
f=fullfile(sessionDir,sprintf('attempt_%05d',status.attempt),'stdout.log');
if ~isfile(f)
    fprintf('目前 attempt %d 尚未產生日誌。\n',status.attempt);return;
end
try
    contents=string(fileread(f));
catch err
    fprintf('暫時無法讀取日誌，請稍後重試。\n%s\n',err.message);return;
end
if strlength(strtrim(contents))==0
    fprintf('目前 attempt %d 的日誌仍為空白，尚不能確認新的 episode 已開始。\n',status.attempt);return;
end
lines=splitlines(contents);
if strlength(lines(end))==0,lines(end)=[];end
fprintf('\n=== Attempt %d | latest %d log lines ===\n',status.attempt,tailLines);
disp(join(lines(max(1,numel(lines)-tailLines+1):end),newline));
end

function showCurriculumProgress(sessionDir,status) %#ok<INUSD>
% Read saved plan/state plus completed stdout rows; never control the run.
planFile=fullfile(sessionDir,'curriculum.json'); stateFile=fullfile(sessionDir,'curriculum_state.json');
if ~isfile(planFile) || ~isfile(stateFile), return; end
try
    plan=jsondecode(fileread(planFile)); state=jsondecode(fileread(stateFile));
    stages=plan.stages; if isstruct(stages), stages=num2cell(stages); end
    assert(iscell(stages),'Curriculum:Snapshot','Invalid stage list.');
    completed=state.completed;
    if iscell(completed) && ~isempty(completed), completed=[completed{:}]; end
    if isempty(completed), completed=struct('id',{},'start_episode',{},'end_episode',{}); end
    if state.stage_index<1 || state.stage_index>numel(stages) || ...
            state.start_episode<0 || numel(completed)~=state.stage_index-1
        error('Curriculum:Snapshot','Inconsistent stage state.');
    end
    fprintf('\n=== Curriculum progress (saved plan/state) ===\n');
    boundary=0;
    for i=1:numel(completed)
        assert(strcmp(completed(i).id,stages{i}.id) && completed(i).start_episode==boundary ...
            && completed(i).end_episode>boundary,'Curriculum:Snapshot','Invalid saved transition.');
        previous=stages{i}; next=stages{i+1}; boundary=completed(i).end_episode;
        fprintf('Transition: Episode %d is last of Stage %d (%s); Episode %d starts Stage %d (%s).\n', ...
            boundary,i,char(previous.id),boundary+1,i+1,char(next.id));
    end
    assert(state.start_episode==boundary,'Curriculum:Snapshot','Stage start disagrees with history.');
    stage=stages{state.stage_index}; rows=trainingcurriculum.log_history(sessionDir);
    episodes=rows(:,1); rewards=rows(:,2); steps=rows(:,3);
    selected=episodes>state.start_episode;
    if any(selected), asOf=max(episodes(selected)); else, asOf=state.start_episode; end
    stageEpisodes=asOf-state.start_episode;
    stageRewards=NaN(stageEpisodes,1); stageSteps=NaN(stageEpisodes,1);
    positions=episodes(selected)-state.start_episode;
    stageRewards(positions)=rewards(selected); stageSteps(positions)=steps(selected);
    progress=trainingcurriculum.progress(stage,stageRewards,stageSteps);
    fprintf('Missing stage log rows: %d (unknown, not compressed).\n',stageEpisodes-nnz(selected));
    fprintf('Current: Stage %d/%d %s; stage episodes %d/%d; data through Episode %d.\n', ...
        state.stage_index,numel(stages),char(stage.id),stageEpisodes,stage.max_episodes,asOf);
    fprintf('Conditions from completed stdout episodes (rounded log estimate; provisional until saved checkpoint): %s\n', ...
        progress.compact);
    formallyComplete=false;
    outcomeFile=fullfile(sessionDir,'curriculum_outcome.json');
    if isfile(outcomeFile)
        outcome=jsondecode(fileread(outcomeFile));
        fprintf('Saved decision through Episode %d: %s (%s).\n',outcome.episodes, ...
            char(outcome.curriculumDecision),char(outcome.curriculumReason));
        if isfield(outcome,'success') && outcome.success
            formallyComplete=true;
            fprintf('Formal result: curriculum completed (%s); success agent: %s\n', ...
                char(outcome.curriculumReason),char(outcome.successAgent));
        end
    end
    if formallyComplete
        fprintf('No remaining course conditions: saved outcome confirms completion. Log estimates above do not override it.\n');
    else
        if state.stage_index==numel(stages), fprintf('Goal: complete course.\n');
        else, fprintf('Goal: enter next stage.\n'); end
        if ~progress.passed
            fprintf('Still needed: %s\n',strjoin(progress.missing,'; '));
        else
            fprintf('Conditions currently pass; formal decision is checked after checkpoint save.\n');
        end
    end
catch err
    fprintf('課程進度暫不可用（保留日誌與狀態原樣）：%s\n',err.message);
end
end
