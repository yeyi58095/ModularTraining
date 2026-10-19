function test_continuous_training()
% No train/sim: real fork, synthetic history, fake attempt engine.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
receipt=jsondecode(fileread(fullfile(root,'tests','output','recovery-smoke-latest.json')));
parent=receipt.sessionDir;
files={'checkpoints/Agent2.mat','curriculum.json','training_guard_state.json'};
before=cellfun(@(f) checkpointreview.sha256(fullfile(parent,f)),files,'UniformOutput',false);
recipe=jsondecode(fileread(fullfile(root,'configs','recovery_v2_18500_continuous.json')));
recipe=rmfield(recipe,'expected_runtime_model_sha256');recipe.checkpoint_episode=2;
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);
recipeFile=fullfile(fixture,'recipe.json');trainingcurriculum.write_json(recipeFile,recipe);
child=trainingtools.prepare_recovery_training(parent,recipeFile);
assert(child.continuousTraining && child.maxAdditionalEpisodes==0);
plan=trainingcurriculum.load_plan(fullfile(child.sessionDir,'curriculum.json'),true);
original=trainingcurriculum.load_plan(fullfile(parent,'curriculum.json'),true);
for k=1:numel(plan.stages)
 assert(strcmp(plan.stages{k}.on_limit,'continue'));
 assert(isequaln(plan.stages{k}.advance_when,original.stages{k}.advance_when));
end
cfg=jsondecode(fileread(fullfile(child.sessionDir,'control.json')));
assert(cfg.maxAttempts==0 && cfg.checkpointEvery>0 && isfile(fullfile(child.sessionDir,'STOP')));
for k=1:numel(files),assert(strcmp(before{k},checkpointreview.sha256(fullfile(parent,files{k}))));end
% Force budget-exceeded but not passed, in this disposable child only.
for k=1:numel(plan.stages)
 plan.stages{k}.max_episodes=1;
 plan.stages{k}.advance_when=struct('metric','reward_mean','window',1,'at_least',500);
end
trainingcurriculum.write_json(fullfile(child.sessionDir,'curriculum.json'),plan);
trainingcurriculum.write_json(fullfile(child.sessionDir,'curriculum_state.json'), ...
 struct('stage_index',1,'start_episode',0,'completed',{{}}));
x=load(fullfile(child.sessionDir,'checkpoints','Agent2.mat'));saved_agent=x.Agent_Stage2;
r=[1000;1000;10;10];n=numel(r);
data=struct('SimulationInfoStorage',[],'TimeStamp',[],'EpisodeIndex',(1:n)', ...
 'EpisodeReward',r,'EpisodeSteps',[3000;3000;10;10],'EpisodeQ0',zeros(n,1), ...
 'EvaluationStatistic',zeros(n,1),'ActorGradientSteps',zeros(n,1),'CriticGradientSteps',zeros(n,1));
savedAgentResult=rl.train.result.rlTrainingResult.fromResultStruct(data,struct('TrainingOpts',rlTrainingOptions));
checkpoint=fullfile(fixture,'history.mat');save(checkpoint,'savedAgentResult','saved_agent');
rules=jsondecode(fileread(fullfile(child.sessionDir,'training_guard.json')));
rules.origin_episode=0;rules.window=1;
ruleFile=fullfile(child.sessionDir,'training_guard.json');trainingcurriculum.write_json(ruleFile,rules);
assert(isempty(trainingguard.check(child.sessionDir,checkpoint)));
gs=jsondecode(fileread(fullfile(child.sessionDir,'training_guard_state.json')));
assert(gs.suspected_regression && ~gs.paused && strcmp(gs.warning,'suspected_regression'));
[context,terminal]=trainingcurriculum.prepare(child.sessionDir,checkpoint);
assert(isempty(terminal) && isinf(context.remainingEpisodes) && context.state.stage_index==1);
% Attempt must still run 100 episodes, not cap at zero or a negative budget.
fid=fopen(fullfile(fixture,'training_engine.m'),'w');
fprintf(fid,"assert(checkpointOverrides.maxEpisodes==100);\nsuccessSummary=struct('success',false,'pause',false,'episodes',4,'averageReward',10);\n");fclose(fid);
cfg.scriptDir=fixture;cfg.attemptDir=fixture;cfg.attempt=1;cfg.resumeCandidates={checkpoint};
entry=fullfile(fixture,'attempt.json');trainingcurriculum.write_json(entry,cfg);checkpoint_attempt(entry);
result=jsondecode(fileread(fullfile(fixture,'result.json')));assert(~result.pause);
% Passing still advances, and the final stage still completes.
assert(strcmp(trainingcurriculum.decide(plan.stages{1},[1000;1000],[3000;3000]).action,'advance'));
context.state.stage_index=numel(plan.stages);context.stage=plan.stages{end};
out=trainingcurriculum.outcome(context,ones(4,1)*1000,ones(4,1)*3000,checkpoint);
assert(out.success && isfile(fullfile(child.sessionDir,'Agent_Success.mat')));
% Defaults and latched pauses remain protective for existing runs.
rules.regression_action='pause';trainingcurriculum.write_json(ruleFile,rules);
terminal=trainingguard.check(child.sessionDir,checkpoint);assert(terminal.pause);
rules.regression_action='monitor';trainingcurriculum.write_json(ruleFile,rules);
terminal=trainingguard.check(child.sessionDir,checkpoint);assert(terminal.pause);
fprintf('PASS continuous fork, source preservation, monitor warning, uncapped attempt, unchanged passing/completion and pause latch. No training.\n');
end
