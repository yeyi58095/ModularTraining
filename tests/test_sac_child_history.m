function test_sac_child_history()
% Fake reports and checkpoint files only; no MATLAB flight or training.
root=fileparts(fileparts(mfilename('fullpath')));folder=tempname(fullfile(root,'tests','output'));mkdir(folder);
old=path;cwd=pwd;cleanup=onCleanup(@() restore(old,cwd)); %#ok<NASGU>
for d=["+trainingtools","+trainingcurriculum","+checkpointreview","+trainingenv","runtime","artifacts"]
    mkdir(fullfile(folder,d));
end
for f=["review_sac_child_history.m","select_sac_review.m"]
    copyfile(fullfile(root,'+trainingtools',f),fullfile(folder,'+trainingtools',f));
end
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
copyfile(fullfile(root,'+checkpointreview','sha256.m'),fullfile(folder,'+checkpointreview'));
put(fullfile(folder,'runtime','training_engine.m'),'% fixture');put(fullfile(folder,'+checkpointreview','random_path.m'),'% fixture');
put(fullfile(folder,'runtime','checkpoint_select_agent.m'),"function checkpoint_select_agent(varargin)"+newline+"end");
put(fullfile(folder,'runtime','checkpoint_resume_state.m'),join([
    "function [h,ep]=checkpoint_resume_state(file)"
    "h=[];[~,n]=fileparts(file);ep=sscanf(n,'Agent%d');if strcmp(n,'Agent_Final'),ep=2100;end"
    "end"],newline));
put(fullfile(folder,'+trainingenv','resolve.m'),"function [file,meta]=resolve(s)"+newline+"file=fullfile(s,'fake.slx');meta=[];"+newline+"end");
put(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(s,varargin)"
    "ep=varargin{2};assert(ismember(ep,1700:100:2000),'Endpoints should be reused');"
    "root=fileparts(mfilename('fullpath'));if ep==1900 && isfile(fullfile(root,'FAIL')),error('Fixture:Fail','Simulated interruption');end"
    "r=make_report(char(s),ep,root);out=tempname(fullfile(s,'reports'));mkdir(out);r.outputDir=out;"
    "trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "f=fopen(fullfile(root,'calls.txt'),'a');fprintf(f,'%d\n',ep);fclose(f);"
    "end"],newline));
put(fullfile(folder,'make_report.m'),join([
    "function r=make_report(s,ep,root)"
    "file=fullfile(s,'checkpoints',sprintf('Agent%d.mat',ep));if ep==2100,file=fullfile(s,'Agent_Final.mat');end"
    "rows={};ids={'random_calm','random_weak_wind'};for stage=1:2,for seed=2000011501:2000011510"
    "rows{end+1}=struct('checkpoint_episode',ep,'stage_id',ids{stage},'seed',seed,'steps',3000, ..."
    "'reached_step_limit',true,'environment_done',false,'wind_east_mps',stage-1,'wind_north_mps',0,'turbulence',0);end,end"
    "r=struct('status','complete','weights_unchanged',true,'use_exploration',false,'max_steps',3000, ..."
    "'route_metrics_enabled',true,'guidance_variant','baseline','results',{rows}, ..."
    "'checkpoints',struct('episode',ep,'sha256',checkpointreview.sha256(file)), ..."
    "'curriculum_sha256',checkpointreview.sha256(fullfile(s,'curriculum.json')), ..."
    "'model_sha256',checkpointreview.sha256(fullfile(s,'fake.slx')), ..."
    "'runtime_sha256',checkpointreview.sha256(fullfile(root,'runtime','training_engine.m')), ..."
    "'random_path_sha256',checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')));"
    "end"],newline));
cd(folder);addpath(folder,fullfile(folder,'runtime'),'-begin');
s=fullfile(folder,'experiments','sac_random_route_v1','runs','20261114_211021_recovery_tp4c32126b');mkdir(s);
mkdir(fullfile(s,'checkpoints'));mkdir(fullfile(s,'reports'));
for ep=1600:100:2000,put(fullfile(s,'checkpoints',sprintf('Agent%d.mat',ep)),string(ep));end
put(fullfile(s,'Agent_Final.mat'),'2100');put(fullfile(s,'fake.slx'),'fixture');
write(fullfile(s,'status.json'),struct('state','paused'));write(fullfile(s,'model.json'),struct('name','sac_paper64'));
write(fullfile(s,'curriculum_outcome.json'),struct('episodes',2100,'curriculumReason','recovery_budget'));
write(fullfile(s,'recovery.json'),struct('parent_session','D:/remote/20261107_132924_recovery_tp578fea3e', ...
    'parent_episode',1600,'parent_sha256',checkpointreview.sha256(fullfile(s,'checkpoints','Agent1600.mat'))));
for f=["curriculum.json","environment.json","training_guard_state.json"],write(fullfile(s,f),struct());end
for ep=[1600 2100]
    name='holdout_1600';if ep==2100,name='final_evaluation';end
    d=fullfile(folder,'artifacts','packages','sac-review-cycle-20261114',name);mkdir(d);
    r=make_report(s,ep,folder);write(fullfile(d,'evaluation.json'),r);
    write(fullfile(d,'complete.json'),struct('checkpoint_sha256',r.checkpoints.sha256, ...
        'files',struct('name','evaluation.json','sha256',checkpointreview.sha256(fullfile(d,'evaluation.json')))));
end
put(fullfile(folder,'FAIL'),'1');
expect(@() trainingtools.review_sac_child_history(),'Fixture:Fail');delete(fullfile(folder,'FAIL'));
bundle=trainingtools.review_sac_child_history();trainingtools.review_sac_child_history();
assert(numel(readlines(fullfile(folder,'calls.txt'),EmptyLineRule='skip'))==4);
q=jsondecode(fileread(fullfile(bundle,'review.json')));assert(strcmp(q.status,'complete') && numel(q.completed_episodes)==6);
put(fullfile(bundle,'episode_1800','evaluation.json'),'corrupt');
expect(@() trainingtools.review_sac_child_history(),'ChildReview:Changed');
write(fullfile(root,'tests','output','sac-child-history-fixture.json'),struct('folder',folder,'bundle',bundle));
fprintf('CHILD_HISTORY_TEST_OK: endpoint reuse, four evaluations, interrupted resume, completed skip, corruption refusal; no training.\n');
end
function put(f,s),id=fopen(f,'w');assert(id~=-1);c=onCleanup(@() fclose(id));fprintf(id,'%s',s);end %#ok<NASGU>
function write(f,s),trainingcurriculum.write_json(f,s);end
function expect(f,id),try,f();error('Test:Expected','Expected failure');catch e,assert(strcmp(e.identifier,id),'Expected %s got %s',id,e.identifier);end,end
function restore(p,d),cd(d);path(p);end
