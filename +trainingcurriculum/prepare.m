function [context,terminal] = prepare(sessionDir,agentFile)
% Transition only at a saved checkpoint boundary, never from stdout counters.
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
model=jsondecode(fileread(fullfile(sessionDir,'model.json')));
assert(strcmp(plan.model,model.name),'Curriculum:Model','Curriculum/model snapshot mismatch.');
rewards=[]; steps=[];
if strlength(string(agentFile))>0
    [history,~,~]=checkpoint_resume_state(agentFile);
    rewards=history.EpisodeReward; steps=history.EpisodeSteps;
end
stateFile=fullfile(sessionDir,'curriculum_state.json');
if isfile(stateFile)
    state=jsondecode(fileread(stateFile));
else
    assert(isempty(rewards),'Curriculum:MissingState', ...
        'Saved episodes exist but curriculum_state.json is missing; refusing to guess the stage.');
    state=struct('stage_index',1,'start_episode',0,'completed',{{}});
end
validateattributes(state.stage_index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(plan.stages)});
validateattributes(state.start_episode,{'numeric'},{'scalar','integer','nonnegative','<=',numel(rewards)});
completed=state.completed;
if ~iscell(completed), completed=num2cell(completed); end
assert(numel(completed)==state.stage_index-1,'Curriculum:State','Inconsistent completed-stage history.');
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
context.remainingEpisodes=context.stage.max_episodes-(numel(rewards)-state.start_episode);
context.environment=struct('trajectory',context.stage.trajectory,'wind',context.stage.wind);
if strcmp(context.stage.trajectory.type,'mat')
    data=trainingcurriculum.load_trajectory(context.stage.trajectory,sessionDir);
    context.environment.trajectory.waypoints=data.waypoints;
    context.environment.trajectory.velocity=data.velocity;
end
fprintf('Curriculum stage %d/%d: %s; starts after episode %d; remaining budget %d.\n', ...
    state.stage_index,numel(plan.stages),context.stage.id,state.start_episode,context.remainingEpisodes);
end
