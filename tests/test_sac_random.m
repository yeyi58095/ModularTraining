function test_sac_random()
% Bounded synthetic CPU training, persistence, routes and gate failure cases.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
plan=trainingcurriculum.load_plan(fullfile(root,'experiments','sac_random_route_v1','curriculum.json'),true);
assert(numel(plan.stages)==4);
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=15;DT=.1;WAYPOINT_SPACING=1.5;
old=rng;cleanup=onCleanup(@() rng(old)); %#ok<NASGU>
a=checkpointreview.scenario(plan.stages{1},root,2000000101);
b=checkpointreview.scenario(plan.stages{4},root,2000000101);
c=checkpointreview.scenario(plan.stages{1},root,2000000102);
assert(isequal(a.waypoints,b.waypoints) && ~isequal(a.waypoints,c.waypoints));
assert(all(isfinite(a.waypoints(:))) && all(a.waypoints(:,3)==70));
ds=vecnorm(diff(a.waypoints),2,2);assert(all(ds>1.49 & ds<=1.50001));
spec=trainingmodels.load_profile('sac_paper64');
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
agent=trainingmodels.build_agent(spec,obs,act,'cpu');trainingmodels.validate_agent(agent,spec);
spec.numWarmStartSteps=8;spec.miniBatchSize=4;
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
env=rlFunctionEnv(obs,act,@step,@reset);
options=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',32,'UseParallel',false, ...
    'Plots','none','Verbose',false,'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
weights=getLearnableParameters(getActor(agent));train(agent,env,options);
assert(~isequaln(weights,getLearnableParameters(getActor(agent))));
file=fullfile(root,'tests','output','sac-paper-fixture.mat');save(file,'agent','-v7');
data=load(file,'agent');trainingmodels.validate_agent(data.agent,spec);
x=saveobj(agent);y=saveobj(data.agent);
for key={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(x.(key{1}),y.(key{1})));
end
train(data.agent,env,options);assert(data.agent.ExperienceBuffer.Length==64);
info=trainingtools.prepare_sac_random_trial('cpu',1);
cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(cfg.maxAttempts==1 && cfg.minWorkers==1 && strcmp(cfg.executionMode,'parallel'));
assert(strcmp(checkpoint_storage_version(info.sessionDir),'-v7'));
stage=plan.stages{1};stage.advance_when=struct('metric','stage_episodes','at_least',1);
context=struct('sessionDir',info.sessionDir,'stage',stage,'stageCount',4, ...
    'state',struct('stage_index',1,'start_episode',0));
r=trainingcurriculum.outcome(context,2500,3000,file);
assert(r.pause && strcmp(r.curriculumReason,'frozen_evaluation_required'));
% A report can grant only the exact model/hash/scenario set; test no sim.
[environment,~]=trainingenv.resolve(info.sessionDir);
report=struct('status','complete','weights_unchanged',true,'use_exploration',false, ...
    'max_steps',3000,'guidance_variant','baseline','route_metrics_enabled',true, ...
    'random_path_sha256',checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')), ...
    'curriculum_sha256',checkpointreview.sha256(fullfile(info.sessionDir,'curriculum.json')), ...
    'model_sha256',checkpointreview.sha256(environment), ...
    'runtime_sha256',checkpointreview.sha256(fullfile(root,'runtime','training_engine.m')), ...
    'checkpoints',struct('episode',1,'sha256',checkpointreview.sha256(file)));
rows=cell(1,5);
for i=1:5
    rows{i}=struct('checkpoint_episode',1,'seed',stage.frozen_gate.seeds(i), ...
        'stage_id',stage.id,'steps',3000,'route_metrics',struct('after_10_seconds', ...
        struct('count',2901,'max_m',5,'rms_m',2)));
end
report.results=rows;dirName=fullfile(info.sessionDir,'reports','evaluation_fixture');mkdir(dirName);
reportFile=fullfile(dirName,'evaluation.json');trainingcurriculum.write_json(reportFile,report);
assert(trainingcurriculum.frozen_gate(context,file));
report.results{1}.steps=100;trainingcurriculum.write_json(reportFile,report);
assert(~trainingcurriculum.frozen_gate(context,file));
report.results=rows;report.use_exploration=true;trainingcurriculum.write_json(reportFile,report);
assert(~trainingcurriculum.frozen_gate(context,file));
report.use_exploration=false;report.checkpoints.sha256='wrong';trainingcurriculum.write_json(reportFile,report);
assert(~trainingcurriculum.frozen_gate(context,file));
report.checkpoints.sha256=checkpointreview.sha256(file);report.results=rows(1:4);
trainingcurriculum.write_json(reportFile,report);assert(~trainingcurriculum.frozen_gate(context,file));
report.results=rows;trainingcurriculum.write_json(reportFile,report);
context.state.stage_index=4;context.stage=plan.stages{4};
assert(~trainingcurriculum.frozen_gate(context,file)); % calm alone is insufficient
fprintf('PASS: paper SAC64,64 synthetic steps,v7 optimizer/replay,seeded route pairing,fail-closed frozen gate.\n');
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=32;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
