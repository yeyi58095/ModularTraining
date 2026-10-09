function result = outcome(context,rewards,steps,agentFile)
% Decisions use saved history. Completion publication is safe to retry.
first=context.state.start_episode+1;
assert(numel(rewards)>=context.state.start_episode,'Curriculum:Rollback','Checkpoint predates the current stage.');
stageRewards=rewards(first:end); stageSteps=steps(first:end);
decision=trainingcurriculum.decide(context.stage,stageRewards,stageSteps);
action=decision.action;
if strcmp(action,'advance') && context.state.stage_index==context.stageCount, action='complete'; end
average=[]; if ~isempty(stageRewards), average=mean(stageRewards(max(1,end-49):end)); end
result=struct('success',strcmp(action,'complete'),'pause',strcmp(action,'pause'), ...
    'episodes',numel(rewards),'averageReward',average,'finalAgent',char(agentFile), ...
    'successAgent','','curriculumDecision',action,'curriculumReason',decision.reason, ...
    'stageId',context.stage.id,'stageIndex',context.state.stage_index, ...
    'stageStartEpisode',context.state.start_episode,'stageEpisodes',numel(stageRewards));
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
