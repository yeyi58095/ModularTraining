function [context,terminal] = prepare(sessionDir,agentFile)
% 段落課程準備：從 checkpoint 的保存歷史驗證階段狀態，在已保存邊界處理 advance。
% 回傳 context 與可能的 terminal；保存 curriculum_state，不初始化 agent，也不從 stdout 猜進度。
% Transition only at a saved checkpoint boundary, never from stdout counters.
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
model=jsondecode(fileread(fullfile(sessionDir,'model.json')));
assert(strcmp(plan.model,model.name),'Curriculum:Model','Curriculum/model snapshot mismatch.');
% 新 run 沒有保存歷史時兩者為空；已有 checkpoint 才讀取真實 reward／steps。
rewards=[]; steps=[];
if strlength(string(agentFile))>0
    [history,~,~]=checkpoint_resume_state(agentFile);
    rewards=history.EpisodeReward; steps=history.EpisodeSteps;
end
stateFile=fullfile(sessionDir,'curriculum_state.json');
% checkpoint 已有歷史但缺失 stage state 時拒絕猜測或重建階段。
if isfile(stateFile)
    state=jsondecode(fileread(stateFile));
else
    assert(isempty(rewards),'Curriculum:MissingState', ...
        'Saved episodes exist but curriculum_state.json is missing; refusing to guess the stage.');
    state=struct('stage_index',1,'start_episode',0,'completed',{{}});
end
validateattributes(state.stage_index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(plan.stages)});
validateattributes(state.start_episode,{'numeric'},{'scalar','integer','nonnegative','<=',numel(rewards)});
% 兼容 singleton struct／array，逐段驗證記錄的邊界連續性。
completed=state.completed;
if ~iscell(completed), completed=num2cell(completed); end
assert(numel(completed)==state.stage_index-1,'Curriculum:State','Inconsistent completed-stage history.');
% boundary 表示上一階段最後一回合；新階段從 boundary+1 開始，不能出現重疊或跳過區間。
boundary=0;
for i=1:numel(completed)
    item=completed{i};
    assert(strcmp(item.id,plan.stages{i}.id) && item.start_episode==boundary && ...
        isscalar(item.end_episode) && isfinite(item.end_episode) && ...
        fix(item.end_episode)==item.end_episode && item.end_episode>boundary, ...
        'Curriculum:State','Invalid stage boundary history.');
    boundary=item.end_episode;
end
assert(state.start_episode==boundary,'Curriculum:State','Stage start does not match completed history.');
context=struct('sessionDir',sessionDir,'state',state,'stageCount',numel(plan.stages), ...
    'stage',plan.stages{state.stage_index},'resumeEpisode',numel(rewards));
terminal=[];
decision=trainingcurriculum.outcome(context,rewards,steps,agentFile);
% 只有保存邊界的 advance 才更新 stage；pause／complete 作 terminal 提前返回。
if strcmp(decision.curriculumDecision,'advance')
    completed{end+1}=struct('id',context.stage.id,'start_episode',state.start_episode, ...
        'end_episode',numel(rewards),'reason',decision.curriculumReason);
    state.completed=completed; state.stage_index=state.stage_index+1;
    state.start_episode=numel(rewards);
    context.state=state; context.stage=plan.stages{state.stage_index};
elseif decision.pause || decision.success
    terminal=decision;
end
trainingcurriculum.write_json(stateFile,state);
% remainingEpisodes 是此階段預算減去已保存階段回合，attempt 會把本段長度裁到剩餘量。
context.remainingEpisodes=context.stage.max_episodes-(numel(rewards)-state.start_episode);
% 同一 agent 延續到下一階段，只切換環境軌跡／風與訓練條件。
context.environment=struct('trajectory',context.stage.trajectory,'wind',context.stage.wind);
if strcmp(context.stage.trajectory.type,'mat')
    data=trainingcurriculum.load_trajectory(context.stage.trajectory,sessionDir);
    context.environment.trajectory.waypoints=data.waypoints;
    context.environment.trajectory.velocity=data.velocity;
end
fprintf('Curriculum stage %d/%d: %s; starts after episode %d; remaining budget %d.\n', ...
    state.stage_index,numel(plan.stages),context.stage.id,state.start_episode,context.remainingEpisodes);
end
