function test_sac_actor_pilot(mode)
% Isolated fake lifecycle; no flight/training. Real recovery tested separately.
if nargin==0,mode="actor";end
root=fileparts(fileparts(mfilename('fullpath')));folder=tempname(fullfile(root,'tests','output'));mkdir(folder);
old=path;cwd=pwd;c=onCleanup(@() restore(old,cwd)); %#ok<NASGU>
for d=["+trainingtools","+trainingcurriculum","+checkpointreview","runtime"] ,mkdir(fullfile(folder,d));end
copyfile(fullfile(root,'+trainingtools','run_sac_actor_pilot.m'),fullfile(folder,'+trainingtools'));
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
put(fullfile(folder,'+checkpointreview','sha256.m'),"function h=sha256(~)"+newline+"h='45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c';"+newline+"end");
put(fullfile(folder,'+trainingtools','preflight_sac_random.m'),"function r=preflight_sac_random(varargin)"+newline+"r=struct('fixture',true);"+newline+"end");
put(fullfile(folder,'+trainingtools','audit_sac_replay_retention.m'),join([
    "function r=audit_sac_replay_retention(~,file)"
    "d=fileparts(file);if endsWith(d,'checkpoints'),d=fileparts(d);end;m=jsondecode(fileread(fullfile(d,'model.json')));"
    "r=struct('source_prefix_retained',true,'source_length',50000,'candidate_length',50000,'candidate_capacity',m.experienceBufferLength);"
    "end"],newline));
put(fullfile(folder,'runtime','checkpoint_resume_state.m'),join([
    "function [h,ep]=checkpoint_resume_state(~)"
    "ep=1700;h=table(ones(1700,1)*2000,ones(1700,1)*3000,'VariableNames',{'EpisodeReward','EpisodeSteps'});"
    "end"],newline));
put(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(s,varargin)"
    "ep=varargin{2};if isempty(ep),ep=1700;end;o=struct(varargin{:});seeds=o.seeds;"
    "rows={};ids={'random_calm','random_weak_wind'};for stage=1:2,for seed=seeds"
    "rows{end+1}=struct('checkpoint_episode',ep,'stage_id',ids{stage},'seed',seed,'steps',3000,'environment_done',false, ..."
    "'reward',2400,'wind_east_mps',stage-1,'wind_north_mps',0,'turbulence',0);end,end"
    "out=tempname(fullfile(s,'reports'));mkdir(out);"
    "r=struct('status','complete','weights_unchanged',true,'use_exploration',false,'max_steps',3000,'results',{rows},'outputDir',out);"
    "for key={'curriculum_sha256','model_sha256','runtime_sha256','random_path_sha256','guidance_variant'},r.(key{1})='fixture';end"
    "trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "end"],newline));
put(fullfile(folder,'+trainingtools','prepare_recovery_training.m'),join([
    "function info=prepare_recovery_training(source,recipeFile)"
    "r=jsondecode(fileread(recipeFile));assert(r.max_additional_episodes==100 && r.episodes_per_process==100);"
    "root=fileparts(fileparts(mfilename('fullpath')));parent=fullfile(root,'experiments','sac_random_route_v1','runs');"
    "child=tempname(parent);mkdir(child);mkdir(fullfile(child,'reports'));"
    "for f={'control.json','recovery.json','curriculum.json','environment.json','training_guard_state.json'},trainingcurriculum.write_json(fullfile(child,f{1}),struct());end"
    "trainingcurriculum.write_json(fullfile(child,'training_guard.json'),struct('origin_episode',1600,'max_additional_episodes',100));"
    "trainingcurriculum.write_json(fullfile(child,'model.json'),struct('actorLearnRate',1.5e-4*r.actor_learning_rate_scale,'criticLearnRate',3e-4,'experienceBufferLength',r.experience_buffer_length));"
    "f=fopen(fullfile(child,'supervisor.lock'),'w');fclose(f);info=struct('sessionDir',child);"
    "end"],newline));
put(fullfile(folder,'retry.m'),join([
    "function info=retry(varargin)"
    "p=inputParser;p.addParameter('resume','');p.addParameter('start',false);p.addParameter('maxAttempts',0);p.addParameter('episodesPerProcess',0);p.parse(varargin{:});"
    "assert(p.Results.start && p.Results.maxAttempts==1 && p.Results.episodesPerProcess==100);child=char(p.Results.resume);"
    "assert(isempty(dir(fullfile(child,'attempt_*'))),'Duplicate training');d=fullfile(child,'attempt_00001');mkdir(d);mkdir(fullfile(child,'diagnostics'));"
    "r=struct('episodes',1700,'curriculumReason','recovery_budget');trainingcurriculum.write_json(fullfile(d,'result.json'),r);"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_outcome.json'),r);"
    "trainingcurriculum.write_json(fullfile(child,'status.json'),struct('state','paused'));"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_state.json'),struct('stage_index',2));"
    "writetable(table(0,'VariableNames',{'ExitCode'}),fullfile(child,'diagnostics','worker_attempts.csv'));"
    "f=fopen(fullfile(child,'Agent_Final.mat'),'w');fprintf(f,'fixture');fclose(f);"
    "pi=System.Diagnostics.ProcessStartInfo;pi.FileName='cmd.exe';pi.Arguments='/c exit 0';pi.UseShellExecute=false;pi.CreateNoWindow=true;"
    "info=struct('supervisor',System.Diagnostics.Process.Start(pi));"
    "end"],newline));
cd(folder);addpath(folder,fullfile(folder,'runtime'),'-begin');clear retry;
s=fullfile(folder,'experiments','sac_random_route_v1','runs','20261114_211021_recovery_tp4c32126b');mkdir(s);mkdir(fullfile(s,'reports'));
write(fullfile(s,'status.json'),struct('state','paused'));
write(fullfile(s,'model.json'),struct('name','sac_paper64','actorLearnRate',1.5e-4,'criticLearnRate',3e-4,'experienceBufferLength',50000));
write(fullfile(s,'curriculum_outcome.json'),struct('episodes',2100,'curriculumReason','recovery_budget'));
write(fullfile(s,'control.json'),struct('trainingDevice','gpu','executionMode','parallel','numWorkers',6,'minWorkers',6));
b=trainingtools.run_sac_actor_pilot(mode);q=jsondecode(fileread(fullfile(b,'review.json')));
assert(strcmp(q.status,'complete') && numel(q.children)==2 && all([q.children.added_episodes]==100));
assert(numel(jsondecode(fileread(fullfile(b,'comparison.json'))))==12);
if mode=="replay_retention"
    protocol=jsondecode(fileread(fullfile(b,'protocol.json')));
    assert(isequal(protocol.replay_capacities(:)',[50000 500000]) && all(protocol.actor_rates==1.5e-4));
    assert(isfile(fullfile(b,'retained500k_final_replay.json')));
    screening=jsondecode(fileread(fullfile(b,'screening.json')));
    assert(~screening.screen_pass && ~screening.automatic_continuation, ...
        'Equal fake results must not pass superiority screen or launch continuation.');
end
trainingtools.run_sac_actor_pilot(mode);
q.status='failed';write(fullfile(b,'review.json'),q);
try,trainingtools.run_sac_actor_pilot(mode);error('Test:Expected','Expected refusal');catch e,assert(strcmp(e.identifier,'ActorPilot:Interrupted'));end
write(fullfile(root,'tests','output',char(mode+"-pilot-fixture.json")),struct('folder',folder,'bundle',b));
fprintf('ACTOR_PILOT_FLOW_OK: two arms x100, three paired reports, no duplicate launch, interrupted-run refusal.\n');
end
function put(f,s),id=fopen(f,'w');assert(id~=-1);c=onCleanup(@() fclose(id));fprintf(id,'%s',s);end %#ok<NASGU>
function write(f,s),trainingcurriculum.write_json(f,s);end
function restore(p,d),cd(d);path(p);clear retry;end
