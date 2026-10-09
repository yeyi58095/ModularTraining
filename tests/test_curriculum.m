function test_curriculum()
% Synthetic saved histories and MAT inputs only. No train() or real pool.
root=fileparts(fileparts(mfilename('fullpath'))); old=path;
guard=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
output=fullfile(root,'tests','output'); if ~isfolder(output), mkdir(output); end
fixture=tempname(output); mkdir(fixture);
plan=curriculum_plan(fullfile(root,'curricula','fixed_to_random.json'));
curriculum_plan(fullfile(root,'curricula','two_mat_then_random.example.json'),checkFiles=false);
stage=plan.stages{1};
stage.advance_when=struct('all',{{struct('metric','stage_episodes','at_least',6), ...
    struct('metric','reward_mean','window',2,'consecutive_windows',3,'at_least',100)}});
stage.max_episodes=10;
assert(strcmp(trainingcurriculum.decide(stage,ones(5,1)*100,ones(5,1)).action,'continue'));
assert(strcmp(trainingcurriculum.decide(stage,ones(6,1)*100,ones(6,1)).action,'advance'));
assert(strcmp(trainingcurriculum.decide(stage,[0;0;200;200;200;200],ones(6,1)).action,'continue'));
assert(strcmp(trainingcurriculum.decide(stage,zeros(10,1),ones(10,1)).action,'pause'));
stage.on_limit='advance';
d=trainingcurriculum.decide(stage,zeros(10,1),ones(10,1));
assert(strcmp(d.action,'advance') && strcmp(d.reason,'episode_budget_reached'));
stage.on_limit='pause';
rate=struct('metric','full_length_rate','window',10,'steps_at_least',3000,'at_least',0.9);
stage.advance_when=struct('any',{{rate,struct('metric','stage_episodes','at_least',20)}});
assert(strcmp(trainingcurriculum.decide(stage,zeros(10,1),[ones(9,1)*3000;100]).action,'advance'));
assert(strcmp(trainingcurriculum.decide(stage,zeros(10,1),[ones(9,1)*3000;NaN]).action,'pause'));

% Validate missing inputs/typos; snapshot and variable mapping survive edits.
input=fullfile(fixture,'input'); mkdir(input);
positions=[50 0 70;51.5 0 70;53 0 70]; velocities=repmat([15 0 0],3,1);
save(fullfile(input,'route.mat'),'positions','velocities');
plan.stages{1}.trajectory=struct('type','mat','file','input/route.mat', ...
    'waypoints_variable','positions','velocity_variable','velocities');
for i=1:2
    plan.stages{i}.advance_when=struct('metric','stage_episodes','at_least',2);
    plan.stages{i}.max_episodes=4;
end
file=fullfile(fixture,'plan.json'); trainingcurriculum.write_json(file,plan);
trainingcurriculum.load_plan(file,true);
bad=plan; bad.stages{1}.advance_when=struct('metric','rewrad_mean','window',2,'at_least',2);
badFile=fullfile(fixture,'bad.json'); trainingcurriculum.write_json(badFile,bad);
reject(@() trainingcurriculum.load_plan(badFile,true),'Curriculum:Invalid');
bad=plan; bad.stages{1}.advance_when=struct('all',{{}});
trainingcurriculum.write_json(badFile,bad);
reject(@() trainingcurriculum.load_plan(badFile,true),'Curriculum:Invalid');
bad=plan; bad.stages{1}.trajectory.file='missing.mat';
trainingcurriculum.write_json(badFile,bad);
reject(@() trainingcurriculum.load_plan(badFile,true),'Curriculum:MissingTrajectory');
bad=plan; bad.stages{1}.wind.turbulence=[0 3];
trainingcurriculum.write_json(badFile,bad);
reject(@() trainingcurriculum.load_plan(badFile,true),'Curriculum:Invalid');

info=retry(curriculum=file,start=false,device="cpu");
reject(@() retry(curriculum=file,targetReward=100,start=false),'Curriculum:Criteria');
cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json'))); assert(cfg.curriculumEnabled);
retry(resume=info.sessionDir,start=false);
reject(@() retry(resume=info.sessionDir,curriculum=file,start=false),'Curriculum:Immutable');
positions(:)=999; save(fullfile(input,'route.mat'),'positions','velocities');
[context,terminal]=trainingcurriculum.prepare(info.sessionDir,'');
assert(isempty(terminal) && context.state.stage_index==1 && context.remainingEpisodes==4);
assert(context.environment.trajectory.waypoints(1,1)==50);

% The real checkpoint reader accepts synthetic R2024b training results.
checkpoint=fullfile(info.sessionDir,'synthetic-history.mat');
saveHistory(checkpoint,[100;100]);
[context,terminal]=trainingcurriculum.prepare(info.sessionDir,checkpoint);
assert(isempty(terminal) && context.state.stage_index==2 && context.state.start_episode==2);
assert(context.remainingEpisodes==4); % Stage 1 episodes do not advance stage 2.
[again,terminal]=trainingcurriculum.prepare(info.sessionDir,checkpoint);
assert(isempty(terminal) && again.state.stage_index==2 && numel(again.state.completed)==1);
saveHistory(checkpoint,[100;100;100;100]);
[~,terminal]=trainingcurriculum.prepare(info.sessionDir,checkpoint);
assert(terminal.success && strcmp(terminal.curriculumDecision,'complete'));
assert(isfile(fullfile(info.sessionDir,'Agent_Success.mat')));
[~,terminal]=trainingcurriculum.prepare(info.sessionDir,checkpoint); assert(terminal.success);
saveHistory(checkpoint,100);
reject(@() trainingcurriculum.prepare(info.sessionDir,checkpoint),'');

% Budget pause leaves a saved checkpoint and cannot publish success.
plan.stages=plan.stages(1);
plan.stages{1}.trajectory=struct('type','fixed_builtin');
plan.stages{1}.advance_when=struct('metric','reward_mean','window',2,'at_least',9999);
trainingcurriculum.write_json(file,plan);
paused=retry(curriculum=file,start=false,device="cpu");
trainingcurriculum.prepare(paused.sessionDir,'');
checkpoint=fullfile(paused.sessionDir,'synthetic-history.mat'); saveHistory(checkpoint,ones(4,1));
[~,terminal]=trainingcurriculum.prepare(paused.sessionDir,checkpoint);
assert(terminal.pause && ~terminal.success && ~isfile(fullfile(paused.sessionDir,'Agent_Success.mat')));

% The actual attempt entry passes the environment and caps segment length.
% Its engine is replaced only inside this private fixture (never the runtime).
fresh=retry(curriculum=file,start=false,device="cpu");
missingStateCheckpoint=fullfile(fresh.sessionDir,'synthetic-history.mat'); saveHistory(missingStateCheckpoint,100);
reject(@() trainingcurriculum.prepare(fresh.sessionDir,missingStateCheckpoint),'Curriculum:MissingState');
mockRuntime=fullfile(fixture,'mock_runtime'); mkdir(mockRuntime);
fid=fopen(fullfile(mockRuntime,'training_engine.m'),'w');
fprintf(fid,'%s\n', ...
    'assert(checkpointOverrides.maxEpisodes==4);', ...
    'assert(strcmp(checkpointOverrides.curriculumContext.environment.trajectory.type,''fixed_builtin''));', ...
    'successSummary=struct(''success'',false,''episodes'',1,''averageReward'',0);');
fclose(fid);
cfg=jsondecode(fileread(fullfile(fresh.sessionDir,'control.json')));
cfg.scriptDir=mockRuntime; cfg.attempt=1; cfg.resumeCandidates={};
cfg.attemptDir=fullfile(fixture,'entry'); mkdir(cfg.attemptDir);
entryFile=fullfile(fixture,'entry.json'); trainingcurriculum.write_json(entryFile,cfg);
checkpoint_attempt(entryFile);
assert(isfile(fullfile(cfg.attemptDir,'result.json')));

% Already-at-budget resume returns pause WITHOUT invoking even the fake engine.
spec=trainingmodels.load_profile(plan.model);
obs=rlNumericSpec([10 1]); act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
saved_agent=trainingmodels.build_agent(spec,obs,act,'cpu');
save(checkpoint,'saved_agent','-append');
cfg.sessionDir=paused.sessionDir; cfg.resumeCandidates={checkpoint}; cfg.attempt=2;
cfg.attemptDir=fullfile(fixture,'pause_entry'); mkdir(cfg.attemptDir);
fid=fopen(fullfile(mockRuntime,'training_engine.m'),'w'); fprintf(fid,'error(''Test:UnexpectedTraining'',''Must pause before training'');\n'); fclose(fid);
trainingcurriculum.write_json(entryFile,cfg);
checkpoint_attempt(entryFile);
result=jsondecode(fileread(fullfile(cfg.attemptDir,'result.json')));
assert(result.pause && ~result.success && result.stageEpisodes==4);
% Verify current MATLAB accepts the non-reward curriculum stop criterion.
opts=rlTrainingOptions('MaxEpisodes',2,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',2);
assert(strcmp(opts.StopTrainingCriteria,'EpisodeCount'));
fprintf('PASS: curriculum schema, all/any, windows, rate, budget, MAT snapshot, stage resume, completion, pause.\n');
end

function saveHistory(file,rewards)
rewards=rewards(:); n=numel(rewards);
data=struct('SimulationInfoStorage',[],'TimeStamp',[], ...
    'EpisodeIndex',(1:n)','EpisodeReward',rewards,'EpisodeSteps',ones(n,1)*3000, ...
    'EpisodeQ0',zeros(n,1),'EvaluationStatistic',zeros(n,1), ...
    'ActorGradientSteps',zeros(n,1),'CriticGradientSteps',zeros(n,1));
savedAgentResult=rl.train.result.rlTrainingResult.fromResultStruct(data,struct('TrainingOpts',rlTrainingOptions));
save(file,'savedAgentResult');
end
function reject(f,id)
rejected=false;
try, f(); catch e, rejected=isempty(id) || strcmp(e.identifier,id); end
assert(rejected,'Expected rejection: %s',id);
end
