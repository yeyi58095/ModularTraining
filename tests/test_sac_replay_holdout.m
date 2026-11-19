function test_sac_replay_holdout()
% Isolated replay of report fixtures; no simulation, training or pool.
root=fileparts(fileparts(mfilename('fullpath')));folder=tempname(fullfile(root,'tests','output'));mkdir(folder);
old=path;cwd=pwd;c=onCleanup(@() restore(old,cwd)); %#ok<NASGU>
for d=["+trainingtools","+trainingcurriculum","+checkpointreview","runtime"],mkdir(fullfile(folder,d));end
copyfile(fullfile(root,'+trainingtools','review_sac_replay_holdout.m'),fullfile(folder,'+trainingtools'));
copyfile(fullfile(root,'+trainingcurriculum','write_json.m'),fullfile(folder,'+trainingcurriculum'));
payload=fullfile(root,'artifacts','incoming','sac-replay-replication-20261119','payload');
prior=fullfile(folder,'artifacts','packages','sac-replay-replication-20261118');mkdir(prior);
for f=["review.json","screening.json"],copyfile(fullfile(payload,f),prior);end
for d=["reference1600","retained500k_evaluation"]
    mkdir(fullfile(prior,d));copyfile(fullfile(payload,d,'evaluation.json'),fullfile(prior,d));
end
ids={'20261114_211021_recovery_tp4c32126b','20261119_004245_recovery_tpf24d3776'};
for k=1:2
    s=fullfile(folder,'experiments','sac_random_route_v1','runs',ids{k});mkdir(s);
    trainingcurriculum.write_json(fullfile(s,'status.json'),struct('state','paused'));
    trainingcurriculum.write_json(fullfile(s,'model.json'),struct('name','sac_paper64'));
end
put(fullfile(folder,'+checkpointreview','sha256.m'),join([
    "function h=sha256(file)"
    "if contains(file,'Agent1600'),h='45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c';else,h='a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6';end"
    "end"],newline));
put(fullfile(folder,'compare_training_checkpoints.m'),join([
    "function r=compare_training_checkpoints(~,varargin)"
    "o=struct(varargin{:});assert(~o.useExploration && o.routeMetrics && o.maxSteps==3000 && ~o.includeLatest && isequal(o.stages,[1 2]) && isequal(o.seeds,2000011901:2000011920));"
    "root=fileparts(mfilename('fullpath'));d='reference1600';if o.finalCheckpoint,d='retained500k_evaluation';assert(isempty(o.episodes));else,assert(o.episodes==1600);end"
    "r=jsondecode(fileread(fullfile(root,'artifacts','packages','sac-replay-replication-20261118',d,'evaluation.json')));"
    "for j=1:numel(r.results),r.results(j).seed=o.seeds(mod(j-1,20)+1);end;r.seeds=o.seeds;"
    "out=tempname(root);mkdir(out);r.outputDir=out;trainingcurriculum.write_json(fullfile(out,'evaluation.json'),r);"
    "end"],newline));
cd(folder);addpath(folder,'-begin');clear compare_training_checkpoints;
b=trainingtools.review_sac_replay_holdout();q=jsondecode(fileread(fullfile(b,'review.json')));
assert(strcmp(q.status,'complete') && numel(q.completed)==2);
a=jsondecode(fileread(fullfile(b,'comparison.json')));assert(numel(a)==4 && all([a.count]==20));
assert(all([a(3:4).full_count]==20) && isequal([a(3:4).full_and_rms10_max20_count],[3 2]));
trainingtools.review_sac_replay_holdout();
q.status='failed';trainingcurriculum.write_json(fullfile(b,'review.json'),q);
try,trainingtools.review_sac_replay_holdout();error('Test:Expected','Expected refusal');catch e,assert(strcmp(e.identifier,'ReplayHoldout:Interrupted'));end
q.simulation_started=false;trainingcurriculum.write_json(fullfile(b,'review.json'),q);
f=fullfile(prior,'reference1600','evaluation.json');bad=jsondecode(fileread(f));bad.runtime_sha256='mismatched-environment';trainingcurriculum.write_json(f,bad);
try,trainingtools.review_sac_replay_holdout();error('Test:Expected','Expected pairing refusal');catch e,assert(strcmp(e.identifier,'ReplayHoldout:Environment'));end
trainingcurriculum.write_json(fullfile(root,'tests','output','replay-holdout-fixture.json'),struct('folder',folder,'bundle',b));
fprintf('REPLAY_HOLDOUT_FLOW_OK: bounded settings, paired reports, precision counts, complete/interrupted guards, mismatched environment refused.\n');
end
function put(f,s),id=fopen(f,'w');assert(id~=-1);c=onCleanup(@() fclose(id));fprintf(id,'%s',s);end %#ok<NASGU>
function restore(p,d),cd(d);path(p);clear compare_training_checkpoints;end
