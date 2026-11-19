function test_sac_replay_extension()
% Isolated fake lifecycle; no training/simulation/pool.
root=fileparts(fileparts(mfilename('fullpath')));folder=tempname(fullfile(root,'tests','output'));mkdir(folder);
old=path;cwd=pwd;c=onCleanup(@()restore(old,cwd)); %#ok<NASGU>
for d=["+trainingtools","+trainingcurriculum","+checkpointreview","runtime"],mkdir(fullfile(folder,d));end
copyfile(fullfile(root,'+trainingtools','run_sac_replay_extension.m'),fullfile(folder,'+trainingtools'));
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
sha='a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6';
put(fullfile(folder,'+checkpointreview','sha256.m'),"function h=sha256(file)"+newline+"h='"+sha+"';if endsWith(file,'curriculum.json'),h='23104371dd53c55385b15bb2341f251a22c0b274bb7a92ea88552ecef0745682';end"+newline+"end");
put(fullfile(folder,'+trainingtools','preflight_sac_random.m'),"function r=preflight_sac_random(varargin)"+newline+"r=struct('fixture',true);"+newline+"end");
put(fullfile(folder,'+trainingtools','audit_sac_replay_retention.m'),join([
    "function r=audit_sac_replay_retention(a,b)"
    "n=337132;if ~strcmp(a,b),n=487132;end;r=struct('source_length',337132,'candidate_capacity',500000,'candidate_length',n,'source_prefix_retained',true);"
    "end"],newline));
put(fullfile(folder,'runtime','checkpoint_resume_state.m'),join([
    "function [h,ep]=checkpoint_resume_state(~)"
    "ep=1750;h=table(ones(1750,1)*3000,'VariableNames',{'EpisodeSteps'});"
    "end"],newline));
put(fullfile(folder,'+trainingtools','prepare_recovery_training.m'),join([
    "function info=prepare_recovery_training(~,recipeFile)"
    "r=jsondecode(fileread(recipeFile));assert(strcmp(r.checkpoint_source,'final') && r.checkpoint_episode==1700 && r.max_additional_episodes==50 && r.episodes_per_process==50 && r.actor_learning_rate_scale==1 && r.experience_buffer_length==500000);"
    "root=fileparts(fileparts(mfilename('fullpath')));child=fullfile(root,'fake_child');mkdir(child);mkdir(fullfile(child,'checkpoints'));"
    "trainingcurriculum.write_json(fullfile(child,'training_guard.json'),struct('origin_episode',1700,'max_additional_episodes',50));"
    "trainingcurriculum.write_json(fullfile(child,'control.json'),struct('checkpointEvery',50,'episodesPerProcess',50));"
    "f=fopen(fullfile(child,'supervisor.lock'),'w');fclose(f);info=struct('sessionDir',child);"
    "end"],newline));
put(fullfile(folder,'retry.m'),join([
    "function info=retry(varargin)"
    "o=struct(varargin{:});assert(o.start && o.maxAttempts==1 && o.episodesPerProcess==50);child=char(o.resume);"
    "assert(isempty(dir(fullfile(child,'attempt_*'))),'Duplicate attempt');mkdir(fullfile(child,'attempt_00001'));mkdir(fullfile(child,'diagnostics'));"
    "p=jsondecode(fileread(fullfile(child,'experiment_protocol.json')));assert(p.training_seed==20261120);"
    "trainingcurriculum.write_json(fullfile(child,'status.json'),struct('state','paused'));"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_outcome.json'),struct('episodes',1750,'curriculumReason','recovery_budget'));"
    "trainingcurriculum.write_json(fullfile(child,'curriculum_state.json'),struct('stage_index',2));"
    "writetable(table(0,'VariableNames',{'ExitCode'}),fullfile(child,'diagnostics','worker_attempts.csv'));"
    "f=fopen(fullfile(child,'Agent_Final.mat'),'w');fprintf(f,'fixture');fclose(f);"
    "pi=System.Diagnostics.ProcessStartInfo;pi.FileName='cmd.exe';pi.Arguments='/c exit 0';pi.UseShellExecute=false;pi.CreateNoWindow=true;"
    "info=struct('supervisor',System.Diagnostics.Process.Start(pi));"
    "end"],newline));
put(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(~,varargin)"
    "o=struct(varargin{:});assert(o.finalCheckpoint && isempty(o.episodes) && ~o.includeLatest && ~o.useExploration && o.routeMetrics && o.maxSteps==3000 && numel(o.seeds)==40);"
    "root=fileparts(mfilename('fullpath'));p=fullfile(root,'artifacts','packages');"
    "r=jsondecode(fileread(fullfile(p,'sac-replay-replication-20261118','retained500k_evaluation','evaluation.json')));"
    "b=jsondecode(fileread(fullfile(p,'sac-replay-holdout-20261119','retained500k','evaluation.json')));r.results=[r.results;b.results];r.checkpoints.episode=1750;r.seeds=o.seeds;"
    "out=tempname(root);mkdir(out);r.outputDir=out;trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "end"],newline));
for names={ {'sac-replay-replication-20261119','sac-replay-replication-20261118','retained500k_evaluation'}, {'sac-replay-holdout-20261119','sac-replay-holdout-20261119','retained500k'} }
    n=names{1};target=fullfile(folder,'artifacts','packages',n{2});mkdir(fullfile(target,n{3}));
    payload=fullfile(root,'artifacts','incoming',n{1},'payload');
    copyfile(fullfile(payload,'review.json'),target);copyfile(fullfile(payload,n{3},'evaluation.json'),fullfile(target,n{3}));
end
source=fullfile(folder,'experiments','sac_random_route_v1','runs','20261119_004245_recovery_tpf24d3776');mkdir(source);
payload=fullfile(root,'artifacts','incoming','sac-replay-replication-20261119','payload','retained500k');
for f=["status.json","model.json","control.json","curriculum_outcome.json","curriculum_state.json"],copyfile(fullfile(payload,f),source);end
cd(folder);addpath(folder,fullfile(folder,'runtime'),'-begin');clear retry compare_training_checkpoints;
b=trainingtools.run_sac_replay_extension();q=jsondecode(fileread(fullfile(b,'review.json')));
assert(strcmp(q.status,'complete') && numel(q.children)==1 && q.children.added_episodes==50 && q.children.new_steps==150000);
a=jsondecode(fileread(fullfile(b,'comparison.json')));assert(numel(a)==4 && all([a.full_count]==20));
trainingtools.run_sac_replay_extension();q.status='failed';trainingcurriculum.write_json(fullfile(b,'review.json'),q);
try,trainingtools.run_sac_replay_extension();error('Test:Expected','Expected refusal');catch e,assert(strcmp(e.identifier,'ReplayExtension:Interrupted'));end
trainingcurriculum.write_json(fullfile(root,'tests','output','replay-extension-fixture.json'),struct('folder',folder,'bundle',b));
fprintf('REPLAY_EXTENSION_FLOW_OK: single50 attempt, retained buffer bound, 80 paired evaluations, no duplicate/restart.\n');
end
function put(f,s),id=fopen(f,'w');assert(id~=-1);c=onCleanup(@()fclose(id));fprintf(id,'%s',s);end %#ok<NASGU>
function restore(p,d),cd(d);path(p);clear retry compare_training_checkpoints;end
