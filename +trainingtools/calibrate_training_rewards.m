function report=calibrate_training_rewards(evaluationDir,outputDir)
% Offline physical-unit reward calibration. Never modifies a model/run/trace.
% Input must be a completed, matching-environment rewardDiagnostics evaluation.
% Output directory must be new; no automatic curriculum threshold or deployment.
arguments
    evaluationDir (1,1) string
    outputDir (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath'))); old=path;
cleanup=onCleanup(@()path(old)); %#ok<NASGU>
addpath(root);
evaluationDir=absolute(evaluationDir,root);outputDir=absolute(outputDir,root);
assert(~isfolder(outputDir) && ~isfile(outputDir),'RewardCalibration:OutputExists', ...
    'Use a new output directory; existing calibration results are preserved.');
sourceFile=fullfile(evaluationDir,'evaluation.json');
source=jsondecode(fileread(sourceFile));
expected='495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be';
assert(strcmp(source.status,'complete') && isfield(source,'reward_definition') && ...
    strcmpi(source.model_sha256,expected),'RewardCalibration:Source', ...
    'Requires completed rewardDiagnostics for the audited spatial environment.');
rows=source.results;if iscell(rows),rows=[rows{:}];end
assert(~isempty(rows),'RewardCalibration:Empty','No traces.');
names={'cross_track','distance_rate','heading','curvature_distance', ...
    'roll_rate','yaw_rate','yaw_tracking','distance_bonus','action_limit','action_change'};
report=struct('schema_version',1,'candidate_version','spatial_reward_v2_candidate_1', ...
    'source_evaluation',char(sourceFile),'source_evaluation_sha256',sha(sourceFile), ...
    'candidate_source_sha256',sha(fullfile(root,'+checkpointreview','spatial_reward_candidate.m')), ...
    'calibration_tool_sha256',sha(string(mfilename('fullpath'))+'.m'), ...
    'model_sha256',source.model_sha256,'checkpoints',source.checkpoints, ...
    'distance_signal','guidance_d in metres; not independent original-route distance', ...
    'distance_weights',[0.2 0.4 0.6],'reference_weight',0.2, ...
    'distance_scale_m',30,'close_bonus_radius_m',10, ...
    'scope','Offline rescoring of frozen trajectories; not learning or threshold validation', ...
    'threshold_status','Uncalibrated: require all stages, failures and held-out trajectories', ...
    'results',{cell(1,numel(rows))});
allSteps=0;
for i=1:numel(rows)
    trace=fullfile(evaluationDir,rows(i).trace);
    x=load(trace,'experience','diagnostics');
    audit=checkpointreview.reward_breakdown(x.experience,x.diagnostics);
    assert(abs(audit.episode_reward-rows(i).reward)<1e-8, ...
        'RewardCalibration:Mismatch','Trace total differs from evaluation.');
    n=audit.steps;allSteps=allSteps+n;
    parts=zeros(n,10);
    for k=1:10
        signal=x.diagnostics.getElement(['reward_' names{k}]).Values;
        values=double(signal.Data(:));parts(:,k)=values(2:end);
    end
    signal=x.diagnostics.getElement('guidance_d').Values;
    d=double(signal.Data(:));d=d(2:end);time=double(signal.Time(:));time=time(2:end);
    row=struct('checkpoint_episode',rows(i).checkpoint_episode, ...
        'stage_id',rows(i).stage_id,'seed',rows(i).seed,'steps',n, ...
        'trace',char(trace),'trace_sha256',sha(trace),'legacy_reward',audit.episode_reward, ...
        'legacy_terms',audit.terms,'guidance_distance_all',stats(d), ...
        'guidance_distance_after_10s',stats(d(time>=10)), ...
        'legacy_curvature_relief_fraction',audit.curvature_gate.applied_fraction);
    if isfield(rows,'route_metrics'),row.independent_route_metrics=rows(i).route_metrics;end
    row.candidates=struct([]);
    for k=1:numel(report.distance_weights)
        weight=report.distance_weights(k);
        [r,newParts]=checkpointreview.spatial_reward_candidate(parts,d,weight);
        candidate=struct('distance_weight',weight,'reward_sum',sum(r), ...
            'reward_per_step',mean(r),'reward_per_step_after_10s',safeMean(r(time>=10)), ...
            'cross_track_sum',sum(newParts(:,1)),'distance_bonus_sum',sum(newParts(:,8)), ...
            'cross_track_delta',sum(newParts(:,1)-parts(:,1)), ...
            'bonus_delta',sum(newParts(:,8)-parts(:,8)), ...
            'unchanged_action_penalty_sum',sum(newParts(:,9:10),'all'));
        if k==1,row.candidates=candidate;else,row.candidates(k)=candidate;end
        assert(isequal(parts(:,[2:7 9:10]),newParts(:,[2:7 9:10])), ...
            'RewardCalibration:Mutation','Unexpected change to retained terms.');
    end
    report.results{i}=row;
end
report.total_steps=allSteps;
% Metamorphic distance sweep holds ALL other terms fixed, unlike real flights.
grid=[0 5 10 20 30 50]';
report.distance_probe_m=grid';report.distance_probe_contribution=zeros(3,numel(grid));
for k=1:3
    r=checkpointreview.spatial_reward_candidate(zeros(numel(grid),10),grid,report.distance_weights(k));
    assert(all(diff(r)<0),'RewardCalibration:Monotonic','Distance reward must decrease.');
    report.distance_probe_contribution(k,:)=r';
end
mkdir(outputDir);
fid=fopen(fullfile(outputDir,'calibration.json'),'w','n','UTF-8');
assert(fid~=-1,'RewardCalibration:Write','Cannot write report.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(report,PrettyPrint=true));
fprintf('Offline reward calibration: %d traces, %d transitions. No training or deployment.\n',numel(rows),allSteps);
end
function p=absolute(p,root)
if ~java.io.File(char(p)).isAbsolute(),p=fullfile(root,p);end
p=string(char(java.io.File(char(p)).getCanonicalPath()));
end
function h=sha(file)
% Hash the exact local input bytes, including MAT source traces.
stream=System.IO.File.OpenRead(char(file));closer=onCleanup(@()stream.Dispose()); %#ok<NASGU>
hasher=System.Security.Cryptography.SHA256.Create();guard=onCleanup(@()hasher.Dispose()); %#ok<NASGU>
h=lower(reshape(dec2hex(uint8(hasher.ComputeHash(stream)),2)',1,[]));
end
function out=stats(d)
out=struct('count',numel(d),'mean_m',safeMean(d),'rms_m',sqrt(safeMean(d.^2)), ...
    'within_10m_fraction',safeMean(double(d<=10)));
end
function y=safeMean(x)
if isempty(x),y=NaN;else,y=mean(x);end
end
