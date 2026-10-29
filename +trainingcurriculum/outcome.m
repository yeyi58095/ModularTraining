function result = outcome(context,rewards,steps,agentFile)
% 段落結果判定：截取當階段歷史、計算過關決策，最後階段 advance 轉為 complete。
% 回傳 result 並寫 curriculum_outcome；完成時發布獨立成功副本，不直接移動下一階段狀態。
% Decisions use saved history. Completion publication is safe to retry.
% 只截取新階段回合，避免前階段的高分把目前階段誤判通過。
first=context.state.start_episode+1;
assert(numel(rewards)>=context.state.start_episode,'Curriculum:Rollback','Checkpoint predates the current stage.');
stageRewards=rewards(first:end); stageSteps=steps(first:end);
decision=trainingcurriculum.decide(context.stage,stageRewards,stageSteps);
action=decision.action;
if strcmp(action,'advance') && isfield(context.stage,'frozen_gate') && ...
        ~trainingcurriculum.frozen_gate(context,agentFile)
    action='pause';decision.reason='frozen_evaluation_required';
end
if strcmp(action,'advance') && context.state.stage_index==context.stageCount, action='complete'; end
average=[]; if ~isempty(stageRewards), average=mean(stageRewards(max(1,end-49):end)); end
result=struct('success',strcmp(action,'complete'),'pause',strcmp(action,'pause'), ...
    'episodes',numel(rewards),'averageReward',average,'finalAgent',char(agentFile), ...
    'successAgent','','curriculumDecision',action,'curriculumReason',decision.reason, ...
    'stageId',context.stage.id,'stageIndex',context.state.stage_index, ...
    'stageStartEpisode',context.state.start_episode,'stageEpisodes',numel(stageRewards));
% 成功成果是已保存 agent 的副本；先寫暫存再發布，不在原 checkpoint 改探索模式。
if result.success
    assert(isfile(agentFile),'Curriculum:MissingAgent','A saved agent is required to complete a curriculum.');
    destination=fullfile(context.sessionDir,'Agent_Success.mat');
    if ~isfile(destination)
        temporary=[tempname(context.sessionDir) '.mat'];
        [ok,message]=copyfile(agentFile,temporary); assert(ok,'%s',message);
        [ok,message]=movefile(temporary,destination); assert(ok,'%s',message);
    end
    result.successAgent=destination;
end
trainingcurriculum.write_json(fullfile(context.sessionDir,'curriculum_outcome.json'),result);
end
