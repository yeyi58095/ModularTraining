function test_sac_review_cycle()
% Isolated fake engine/evaluator: no flights, no training, no worker pool.
root=fileparts(fileparts(mfilename('fullpath')));
folder=tempname(fullfile(root,'tests','output')); mkdir(folder);
oldPath=path; oldFolder=pwd; restore=onCleanup(@() restoreCaller(oldPath,oldFolder)); %#ok<NASGU>
for name=["+trainingtools","+checkpointreview","+trainingcurriculum","+trainingenv","runtime","artifacts","configs"]
    mkdir(fullfile(folder,name));
end
for name=["run_sac_review_cycle.m","select_sac_review.m"]
    copyfile(fullfile(root,'+trainingtools',name),fullfile(folder,'+trainingtools',name));
end
copyfile(fullfile(root,'+checkpointreview','sha256.m'),fullfile(folder,'+checkpointreview'));
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
copyfile(fullfile(root,'configs','sac_wind_actor_half_extend_1500.json'),fullfile(folder,'configs'));
put(fullfile(folder,'+trainingenv','resolve.m'),"function resolve(~)"+newline+"end");
put(fullfile(folder,'+trainingtools','preflight_sac_random.m'),"function r=preflight_sac_random(varargin)"+newline+"r=struct('scope','fixture only');"+newline+"end");
put(fullfile(folder,'runtime','checkpoint_select_agent.m'),"function checkpoint_select_agent(varargin)"+newline+"end");
put(fullfile(folder,'runtime','checkpoint_resume_state.m'),join([
    "function [h,ep]=checkpoint_resume_state(file)"
    "[d,n]=fileparts(file);ep=sscanf(n,'Agent%d');"
    "if strcmp(n,'Agent_Final'),r=jsondecode(fileread(fullfile(d,'curriculum_outcome.json')));ep=r.episodes;end"
    "h=table(repmat(2000,ep,1),repmat(3000,ep,1),'VariableNames',{'EpisodeReward','EpisodeSteps'});"
    "end"],newline));
put(fullfile(folder,'+checkpointreview','random_path.m'),"% fixture");
put(fullfile(folder,'runtime','training_engine.m'),"% fixture");
put(fullfile(folder,'+trainingcurriculum','load_plan.m'),join([
    "function plan=load_plan(varargin)"
    "s=struct('frozen_gate',struct('seeds',2000000101:2000000105));"
    "plan=struct('stages',{{s,s,s,s}});"
    "end"],newline));
put(fullfile(folder,'+trainingcurriculum','frozen_gate.m'),join([
    "function passed=frozen_gate(varargin)"
    "passed=~isfile(fullfile(fileparts(fileparts(mfilename('fullpath'))),'FAIL_GATE'));"
    "end"],newline));
put(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(session,varargin)"
    "p=inputParser; p.addParameter('episodes',[]); p.addParameter('finalCheckpoint',false);"
    "p.addParameter('includeLatest',false); p.addParameter('stages',[]); p.addParameter('seeds',[]);"
    "p.addParameter('maxSteps',3000); p.addParameter('useExploration',false); p.addParameter('routeMetrics',true);"
    "p.parse(varargin{:}); o=p.Results; ep=o.episodes;"
    "if o.finalCheckpoint, q=jsondecode(fileread(fullfile(session,'curriculum_outcome.json'))); ep=q.episodes; end"
    "out=tempname(fullfile(session,'reports')); mkdir(out); rows={}; ids={'random_calm','random_weak_wind','random_medium_wind'};"
    "for stage=o.stages, for j=1:numel(o.seeds)"
    "n=8; if ep==1700 || o.finalCheckpoint,n=10;end"
    "if isfile(fullfile(fileparts(mfilename('fullpath')),'FAIL_ALL')),n=0;end"
    "if o.seeds(1)==2000011501 && ep==1700 && isfile(fullfile(fileparts(mfilename('fullpath')),'FAIL_HOLDOUT')),n=0;end"
    "full=j<=n; rows{end+1}=struct('checkpoint_episode',ep,'stage_id',ids{stage},'seed',o.seeds(j), ..."
    "'steps',100+2900*full,'reached_step_limit',full,'environment_done',~full,'wind_east_mps',stage-1,'wind_north_mps',0,'turbulence',0);"
    "end,end"
    "r=struct('status','complete','weights_unchanged',true,'use_exploration',false,'max_steps',3000,'results',{rows},'outputDir',out);"
    "trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "end"],newline));
put(fullfile(folder,'+trainingtools','prepare_recovery_training.m'),join([
    "function info=prepare_recovery_training(source,recipeFile)"
    "root=fileparts(fileparts(mfilename('fullpath'))); recipe=jsondecode(fileread(recipeFile));"
    "assert(recipe.checkpoint_episode==1700 && recipe.max_additional_episodes==500);"
    "parent=fullfile(root,'experiments','sac_random_route_v1','runs'); child=tempname(parent); mkdir(child); mkdir(fullfile(child,'reports'));"
    "trainingcurriculum.write_json(fullfile(child,'status.json'),struct('state','paused'));"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_state.json'),struct('stage_index',2));"
    "trainingcurriculum.write_json(fullfile(child,'curriculum.json'),struct());"
    "info=struct('sessionDir',child);"
    "end"],newline));
put(fullfile(folder,'retry.m'),join([
    "function info=retry(varargin)"
    "p=inputParser;p.addParameter('resume','');p.addParameter('start',false);p.addParameter('maxAttempts',0);p.parse(varargin{:});"
    "assert(p.Results.start && p.Results.maxAttempts==1); child=char(p.Results.resume);"
    "count=numel(dir(fullfile(child,'attempt_*')))+1; assert(count<=2,'Duplicate launch');"
    "d=fullfile(child,sprintf('attempt_%05d',count));mkdir(d);"
    "if count==1,ep=1800;stage=2;reason='frozen_evaluation_required';else,ep=2200;stage=3;reason='recovery_budget';end"
    "r=struct('episodes',ep,'stageIndex',stage,'success',false,'curriculumReason',reason);"
    "if count==2,r.pauseReason=reason;end"
    "trainingcurriculum.write_json(fullfile(d,'result.json'),r);"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_outcome.json'),r);"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_state.json'),struct('stage_index',stage));"
    "trainingcurriculum.write_json(fullfile(child,'training_guard_state.json'),struct('paused',count==2));"
    "if ~isfolder(fullfile(child,'diagnostics')),mkdir(fullfile(child,'diagnostics'));end"
    "writetable(table(0,'VariableNames',{'ExitCode'}),fullfile(child,'diagnostics','worker_attempts.csv'));"
    "f=fopen(fullfile(child,'Agent_Final.mat'),'w');fprintf(f,'%d',ep);fclose(f);"
    "pi=System.Diagnostics.ProcessStartInfo;pi.FileName='cmd.exe';pi.Arguments='/c exit 0';pi.UseShellExecute=false;pi.CreateNoWindow=true;"
    "info=struct('supervisor',System.Diagnostics.Process.Start(pi));"
    "end"],newline));
cd(folder); addpath(folder,fullfile(folder,'runtime'),'-begin'); clear retry;
source=fullfile(folder,'experiments','sac_random_route_v1','runs','20261107_132924_recovery_tp578fea3e');
mkdir(source);mkdir(fullfile(source,'checkpoints'));mkdir(fullfile(source,'reports'));
put(fullfile(folder,'artifacts','sac-wind-actor-half-1500-run.txt'),source);
for ep=1500:100:2000,put(fullfile(source,'checkpoints',sprintf('Agent%d.mat',ep)),string(ep));end
write(fullfile(source,'model.json'),struct('name','sac_paper64','actorLearnRate',1.5e-4,'criticLearnRate',3e-4));
write(fullfile(source,'control.json'),struct('trainingDevice','gpu','executionMode','parallel', ...
    'numWorkers',6,'minWorkers',6,'checkpointEvery',100));
write(fullfile(source,'status.json'),struct('state','paused'));
write(fullfile(source,'curriculum_outcome.json'),struct('episodes',2000,'curriculumReason','recovery_budget'));
for name=["curriculum.json","environment.json","recovery.json"],write(fullfile(source,name),struct());end
bundle=trainingtools.run_sac_review_cycle();
ledger=read(fullfile(bundle,'cycle.json'));
assert(strcmp(ledger.phase,'complete') && ledger.launches==2 && ledger.added_episodes==500 && ledger.final_state.stage_index==3);
trainingtools.run_sac_review_cycle(); % Completed cycle must never train again.
assert(numel(dir(fullfile(ledger.child,'attempt_*')))==2);
% Corrupted cached evaluation must fail before preparation/launch.
write(fullfile(bundle,'cycle.json'),struct('phase','selection_evaluation','launch_intent',false));
put(fullfile(bundle,'selection_1500','evaluation.json'),'corrupt');
expectFailure(@() trainingtools.run_sac_review_cycle(),'Review:Changed');
% Direct policy checks: missing pair, actual-wind insufficiency and no candidate.
r=read(fullfile(bundle,'selection_1600','evaluation.json'));
d=trainingtools.select_sac_review({r},2000011401:2000011410,1600);assert(d.selected_episode==1600);
r.results(1).seed=r.results(2).seed;
expectFailure(@() trainingtools.select_sac_review({r},2000011401:2000011410,1600),'Review:Report');
r=read(fullfile(bundle,'selection_1600','evaluation.json'));
for k=1:numel(r.results),r.results(k).wind_east_mps=0;end
d=trainingtools.select_sac_review({r},2000011401:2000011410,1600);assert(isempty(d.selected_episode));
% Interrupted launch record must refuse even when a child appears stopped.
write(fullfile(bundle,'cycle.json'),struct('phase','training','launch_intent',true));
expectFailure(@() trainingtools.run_sac_review_cycle(),'Review:Interrupted');
assert(startsWith(bundle,folder+string(filesep)),'Test path must stay in isolated fixture');
movefile(bundle,[bundle '_first']);
put(fullfile(folder,'FAIL_ALL'),'1');
bundle=trainingtools.run_sac_review_cycle(); q=read(fullfile(bundle,'cycle.json'));
assert(strcmp(q.phase,'no_candidate') && ~q.prepare_intent && ~q.launch_intent);
movefile(bundle,[bundle '_none']); delete(fullfile(folder,'FAIL_ALL'));
put(fullfile(folder,'FAIL_HOLDOUT'),'1');
bundle=trainingtools.run_sac_review_cycle(); q=read(fullfile(bundle,'cycle.json'));
assert(strcmp(q.phase,'holdout_failed') && ~q.prepare_intent && ~q.launch_intent);
movefile(bundle,[bundle '_holdout']); delete(fullfile(folder,'FAIL_HOLDOUT'));
put(fullfile(folder,'FAIL_GATE'),'1');
bundle=trainingtools.run_sac_review_cycle(); q=read(fullfile(bundle,'cycle.json'));
assert(strcmp(q.phase,'complete') && q.launches==1 && q.final_state.stage_index==2 && q.added_episodes==100);
write(fullfile(root,'tests','output','sac-review-cycle-fixture-latest.json'),struct('folder',folder,'bundle',bundle,'child',q.child));
fprintf('REVIEW_CYCLE_TEST_OK: selection, holdout, bounded stage advance, no duplicate launch, corruption refusal.\n');
end
function put(file,text)
fid=fopen(file,'w');assert(fid~=-1);c=onCleanup(@() fclose(fid));fprintf(fid,'%s',text); %#ok<NASGU>
end
function write(file,value),trainingcurriculum.write_json(file,value);end
function value=read(file),value=jsondecode(fileread(file));end
function expectFailure(f,id)
try,f();error('Test:Expected','Expected failure');catch e,assert(strcmp(e.identifier,id),'Expected %s, got %s',id,e.identifier);end
end
function restoreCaller(p,d),cd(d);path(p);clear retry;end
