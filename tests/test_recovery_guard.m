function test_recovery_guard()
% Real checkpoint preparation and a fake engine; never call train or sim.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root,fullfile(root,'runtime'));
settings=jsondecode(fileread(fullfile(root,'configs','recovery_actor_half.json')));
r=settings.guard; r.window=2; r.patience=3;
rewards=[1000 1000 100 100 100 100 100 100]; steps=rewards*2;
a=trainingguard.assess(rewards,steps,0,r); assert(a.suspected_regression && a.low_windows==3);
a=trainingguard.assess(rewards(1:7),steps(1:7),0,r); assert(~a.suspected_regression);
a=trainingguard.assess(rewards,steps,2,r); assert(~a.suspected_regression); % stage reset
a=trainingguard.assess(rewards,ones(size(steps))*2000,0,r); assert(~a.suspected_regression); % both metrics
a=trainingguard.assess([rewards 1200 1200],[steps 2400 2400],0,r); assert(~a.suspected_regression);
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
source=receipt.sessionDir;
files={'curriculum_state.json','model.json','control.json','status.json','checkpoints/Agent2.mat'};
before=cellfun(@(f) checkpointreview.sha256(fullfile(source,f)),files,'UniformOutput',false);
fixture=tempname(fullfile(root,'tests','output')); mkdir(fixture);
settings.checkpoint_episode=2; settings.episodes_per_process=1; settings.max_additional_episodes=4;
settings.guard.window=1; settings.guard.min_reference_reward=1; settings.guard.min_reference_steps=1;
ruleFile=fullfile(fixture,'recipe.json'); trainingcurriculum.write_json(ruleFile,settings);
info=prepare_recovery_training(source,ruleFile);
state=jsondecode(fileread(fullfile(info.sessionDir,'curriculum_state.json')));
assert(state.stage_index==2 && state.start_episode==1);
spec=jsondecode(fileread(fullfile(info.sessionDir,'model.json')));
assert(spec.actorLearnRate==2.5e-5);
target=fullfile(info.sessionDir,'checkpoints','Agent2.mat');
lineage=jsondecode(fileread(fullfile(info.sessionDir,'recovery.json')));
assert(strcmp(lineage.child_checkpoint_sha256,checkpointreview.sha256(target)));
original=load(fullfile(source,'checkpoints','Agent2.mat'),'saved_agent');
child=load(target,'Agent_Stage2');
assert(isequaln(getLearnableParameters(getActor(original.saved_agent)),getLearnableParameters(getActor(child.Agent_Stage2))));
assert(isequaln(getLearnableParameters(getCritic(original.saved_agent)),getLearnableParameters(getCritic(child.Agent_Stage2))));
trainingmodels.validate_agent(child.Agent_Stage2,spec);
for i=1:numel(files), assert(strcmp(before{i},checkpointreview.sha256(fullfile(source,files{i})))); end
cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(strcmp(cfg.sessionDir,info.sessionDir) && cfg.episodesPerProcess==1);
assert(~isfolder(fullfile(info.sessionDir,'attempt_00001')) && isfile(fullfile(info.sessionDir,'STOP')));
rules=jsondecode(fileread(fullfile(info.sessionDir,'training_guard.json')));
% A partial remaining recovery budget must cap the next process, even when
% the curriculum and configured process size would otherwise allow 100.
plan=trainingcurriculum.load_plan(fullfile(info.sessionDir,'curriculum.json'),false);
plan.stages{2}.max_episodes=100;
plan.stages{2}.advance_when=struct('metric','stage_episodes','at_least',100);
trainingcurriculum.write_json(fullfile(info.sessionDir,'curriculum.json'),plan);
rules.max_additional_episodes=1;
trainingcurriculum.write_json(fullfile(info.sessionDir,'training_guard.json'),rules);
fid=fopen(fullfile(fixture,'training_engine.m'),'w');
fprintf(fid,"assert(checkpointOverrides.maxEpisodes==1);\nsuccessSummary=struct('success',false,'pause',false,'episodes',2,'averageReward',0,'budgetCapTest',true);\n"); fclose(fid);
cfg.scriptDir=fixture; cfg.attemptDir=fixture; cfg.attempt=1; cfg.resumeCandidates={target};
cfg.episodesPerProcess=100;
config=fullfile(fixture,'attempt.json'); trainingcurriculum.write_json(config,cfg);
checkpoint_attempt(config);
result=jsondecode(fileread(fullfile(fixture,'result.json'))); assert(result.budgetCapTest);
rules.origin_episode=0; rules.max_additional_episodes=2;
trainingcurriculum.write_json(fullfile(info.sessionDir,'training_guard.json'),rules);
terminal=trainingguard.check(info.sessionDir,target); assert(strcmp(terminal.pauseReason,'recovery_budget'));
savedOutcome=jsondecode(fileread(fullfile(info.sessionDir,'curriculum_outcome.json')));
assert(savedOutcome.pause && strcmp(savedOutcome.pauseReason,'recovery_budget'));
rules.max_additional_episodes=100;
trainingcurriculum.write_json(fullfile(info.sessionDir,'training_guard.json'),rules);
terminal=trainingguard.check(info.sessionDir,target); assert(terminal.pause); % latched
fid=fopen(fullfile(fixture,'training_engine.m'),'w'); fprintf(fid,"error('Test:EngineCalled','Must not run');\n"); fclose(fid);
cfg.scriptDir=fixture; cfg.attemptDir=fixture; cfg.attempt=1; cfg.resumeCandidates={target};
config=fullfile(fixture,'attempt.json'); trainingcurriculum.write_json(config,cfg);
checkpoint_attempt(config);
result=jsondecode(fileread(fullfile(fixture,'result.json')));
assert(result.pause && strcmp(result.pauseReason,'recovery_budget'));
trainingcurriculum.write_json(fullfile(root,'tests','output','recovery-smoke-latest.json'),info);
fprintf('PASS stage-isolated guard, forked weights/history, source preservation, saved-boundary pause and latched preflight; no train/sim.\n');
end
