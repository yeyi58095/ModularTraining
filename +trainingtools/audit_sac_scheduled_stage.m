function summary=audit_sac_scheduled_stage(session,officialPlanFile,stageIndex,finalPath)
% Assess an immutable saved endpoint against the original course without authorizing a transition.
arguments
    session (1,1) string
    officialPlanFile (1,1) string
    stageIndex (1,1) double {mustBeInteger,mustBePositive}
    finalPath (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; restore=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'),'-begin');
session=trainingtools.local_data_path(root,session);
officialPlanFile=trainingtools.local_data_path(root,officialPlanFile);
finalPath=trainingtools.local_data_path(root,finalPath);
assert(strcmp(finalPath,fullfile(session,'Agent_Final.mat')), ...
    'ScheduledSAC:AuditSource','Use the current saved endpoint of this scheduled run.');
original=trainingcurriculum.load_plan(officialPlanFile,true);
scheduledPlanFile=fullfile(session,'curriculum.json');
scheduled=trainingcurriculum.load_plan(scheduledPlanFile,true);
assert(strcmp(original.model,'sac_paper64') && ...
    strcmp(scheduled.model,'sac_paper64_fresh500k') && ...
    strcmp(original.environment,scheduled.environment) && ...
    numel(original.stages)==4 && numel(scheduled.stages)==4 && stageIndex<=4, ...
    'ScheduledSAC:AuditCourse','Unexpected official or scheduled course.');
for k=1:numel(original.stages)
    a=original.stages{k}; b=scheduled.stages{k};
    assert(strcmp(a.id,b.id) && isequal(a.trajectory,b.trajectory) && isequal(a.wind,b.wind), ...
        'ScheduledSAC:AuditCourse','The route or wind definition differs from the original stage.');
end
lock=System.IO.File.Open(fullfile(session,'supervisor.lock'),System.IO.FileMode.Open, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose());
status=read(fullfile(session,'status.json'));
state=read(fullfile(session,'curriculum_state.json'));
assert(strcmp(status.state,'paused') && state.stage_index==stageIndex, ...
    'ScheduledSAC:AuditState','Expected the scheduled stage to be saved and paused.');
[history,last]=checkpoint_resume_state(finalPath);
stage=original.stages{stageIndex};
range=state.start_episode+1:last;
assert(numel(range)==scheduled.stages{stageIndex}.max_episodes, ...
    'ScheduledSAC:AuditBudget','Saved stage length differs from the declared quota.');
training=trainingcurriculum.progress(stage,history.EpisodeReward(range),history.EpisodeSteps(range));
continuity=validateStageInitial(session,stageIndex,finalPath,sum(history.EpisodeSteps(range)));
before=checkpointreview.sha256(finalPath);
[model,environment]=trainingenv.resolve(session);
environmentHash=checkpointreview.sha256(model);
fixture=fullfile(fileparts(officialPlanFile),sprintf('audit_stage%d',stageIndex));
assert(~isfolder(fixture),'ScheduledSAC:AuditExisting','Existing audit is preserved for inspection.');
mkdir(fixture);
fixturePlan=fullfile(fixture,'curriculum.json');
copyfile(officialPlanFile,fixturePlan);
trainingenv.snapshot(fullfile(session,'environment.json'),fileparts(model),fixture);
copy=fullfile(fixture,'Agent_Final.mat');
copyfile(finalPath,copy);
assert(strcmp(checkpointreview.sha256(copy),before) && ...
    strcmp(checkpointreview.sha256(trainingenv.resolve(fixture)),environmentHash), ...
    'ScheduledSAC:AuditCopy','Frozen endpoint or environment copy differs.');
write(fullfile(fixture,'status.json'),struct('state','paused'));
fid=fopen(fullfile(fixture,'supervisor.lock'),'w');
assert(fid>=0,'ScheduledSAC:AuditLock','Could not initialize the independent audit lock.');
fclose(fid);
clear unlock
stages=unique([1 stageIndex]); seeds=stage.frozen_gate.seeds(:)';
report=compare_training_checkpoints(string(fixture),episodes=[],includeLatest=false, ...
    finalCheckpoint=true,stages=stages,seeds=seeds,maxSteps=3000,routeMetrics=true,useExploration=false);
assert(strcmp(report.status,'complete') && report.weights_unchanged && ~report.use_exploration && ...
    report.route_metrics_enabled && strcmp(report.guidance_variant,'baseline') && ...
    strcmp(report.model_sha256,environmentHash) && ...
    strcmp(report.curriculum_sha256,checkpointreview.sha256(officialPlanFile)) && ...
    numel(report.checkpoints)==1 && strcmp(report.checkpoints{1}.sha256,before) && ...
    report.checkpoints{1}.episode==last && numel(report.results)==numel(stages)*numel(seeds), ...
    'ScheduledSAC:AuditReport','Incomplete or different checkpoint evaluation.');
context=struct('sessionDir',fixture,'stage',stage,'state',struct('stage_index',stageIndex));
frozen=trainingcurriculum.frozen_gate(context,copy);
rows=[report.results{:}];
full=[rows.steps]==3000 & ~[rows.environment_done];
precision=false(size(full));
for k=find(full)
    m=rows(k).route_metrics.after_10_seconds;
    precision(k)=m.count>0 && m.rms_m<=stage.frozen_gate.max_rms_m && m.max_m<=stage.frozen_gate.max_distance_m;
end
assert(strcmp(checkpointreview.sha256(finalPath),before) && strcmp(checkpointreview.sha256(copy),before), ...
    'ScheduledSAC:AuditSource','Source changed during the offline evaluation.');
summary=struct('schema_version',1,'phase',stageIndex,'stage_id',stage.id,'episode',last, ...
    'phase_episodes',numel(range),'source_run',session,'checkpoint_sha256',before, ...
    'official_curriculum_sha256',report.curriculum_sha256, ...
    'scheduled_curriculum_sha256',checkpointreview.sha256(scheduledPlanFile), ...
    'environment_id',environment.id,'environment_model_sha256',environmentHash, ...
    'runtime_sha256',report.runtime_sha256,'training_conditions_pass',training.passed, ...
    'training_progress',training,'continuity',continuity,'frozen_criteria_pass',frozen, ...
    'meets_original_criteria',training.passed && frozen, ...
    'evaluation_case_count',numel(rows),'full_count',nnz(full),'full_precision_count',nnz(precision), ...
    'report',fullfile(report.outputDir,'evaluation.json'), ...
    'scope','Original numeric and frozen criteria scored independently after a scheduled boundary.');
write(fullfile(fixture,'summary.json'),summary);
fprintf('Stage %d audit: %d/%d flights reached 3000; %d meet precision; meets original criteria=%d.\n', ...
    stageIndex,nnz(full),numel(rows),nnz(precision),summary.meets_original_criteria);
end

function evidence=validateStageInitial(session,stage,finalPath,newSteps)
logDir=fullfile(session,'runs',sprintf('r%06d',stage));
file=fullfile(logDir,'Agent_Initial.mat');
initial=load(file,'Agent_Stage2');
endpoint=load(finalPath,'Agent_Stage2');
first=saveobj(initial.Agent_Stage2);
finalLength=endpoint.Agent_Stage2.ExperienceBuffer.Length;
assert(isa(initial.Agent_Stage2,'rl.agent.rlSACAgent') && ...
    first.ExperienceBuffer.MaxLength==500000 && ...
    finalLength==min(500000,first.ExperienceBuffer.Length+newSteps), ...
    'ScheduledSAC:Continuity','Unexpected replay at the saved stage endpoints.');
evidence=struct('initial_sha256',checkpointreview.sha256(file), ...
    'initial_replay_length',first.ExperienceBuffer.Length,'final_replay_length',finalLength, ...
    'new_environment_steps',newSteps,'previous_final_sha256','');
if stage==1
    assert(first.ExperienceBuffer.Length==0,'ScheduledSAC:Continuity','An inherited replay buffer was supplied.');
    return
end
source=fullfile(session,'runs',sprintf('r%06d',stage-1),'Agent_Final.mat');
previous=load(source,'Agent_Stage2');
prior=saveobj(previous.Agent_Stage2);
for f={'AgentOptions','ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    field=f{1};
    assert(isequaln(first.(field),prior.(field)),'ScheduledSAC:Continuity','Changed %s before training.',field);
end
for f={'Actor','Critic','TargetCritic'}
    field=f{1};
    assert(numel(first.(field))==numel(prior.(field)),'ScheduledSAC:Continuity','Network count changed.');
    for k=1:numel(first.(field))
        assert(isequaln(getLearnableParameters(first.(field)(k)),getLearnableParameters(prior.(field)(k))), ...
            'ScheduledSAC:Continuity','Changed %s weights before training.',field);
    end
end
assert(first.ExperienceBuffer.Length==prior.ExperienceBuffer.Length,'ScheduledSAC:Continuity','Replay length changed.');
[x,ids]=getLastNData(first.ExperienceBuffer,first.ExperienceBuffer.Length);
[y,priorIDs]=getLastNData(prior.ExperienceBuffer,prior.ExperienceBuffer.Length);
assert(isequaln(x,y) && isequaln(ids,priorIDs), ...
    'ScheduledSAC:Continuity','Replay contents or source IDs changed before training.');
evidence.previous_final_sha256=checkpointreview.sha256(source);
end

function result=read(file)
result=jsondecode(fileread(file));
end

function write(file,value)
trainingcurriculum.write_json(file,value);
end
