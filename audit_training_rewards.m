function audit=audit_training_rewards(evaluationDir)
% 從完成的 rewardDiagnostics 評估拆解 reward；不訓練、不修改 checkpoint。
arguments
    evaluationDir (1,1) string
end
root=fileparts(mfilename('fullpath'));old=path;guard=onCleanup(@()path(old)); %#ok<NASGU>
addpath(root);
if ~java.io.File(char(evaluationDir)).isAbsolute(),evaluationDir=fullfile(root,evaluationDir);end
report=jsondecode(fileread(fullfile(evaluationDir,'evaluation.json')));
assert(strcmp(report.status,'complete') && isfield(report,'reward_definition'), ...
    'RewardAudit:Missing','Use a completed compare_training_checkpoints(...,rewardDiagnostics=true) evaluation.');
rows=report.results;if iscell(rows),rows=[rows{:}];end
audit=struct('schema_version',1,'evaluation',char(evaluationDir), ...
    'model_sha256',report.model_sha256,'checkpoint_sources',report.checkpoints, ...
    'definition',report.reward_definition,'results',{cell(1,numel(rows))});
for i=1:numel(rows)
    x=load(fullfile(evaluationDir,rows(i).trace),'experience','diagnostics');
    row=checkpointreview.reward_breakdown(x.experience,x.diagnostics);
    assert(abs(row.episode_reward-rows(i).reward)<1e-8,'RewardAudit:Report','Trace/report mismatch.');
    row.checkpoint_episode=rows(i).checkpoint_episode;row.stage_id=rows(i).stage_id;row.seed=rows(i).seed;
    audit.results{i}=row;
end
file=fullfile(evaluationDir,'reward_breakdown.json');
fid=fopen(file,'w','n','UTF-8');assert(fid~=-1,'RewardAudit:Write','Cannot write report.');
closer=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(audit,PrettyPrint=true)); %#ok<NASGU>
fprintf('Reward audit only: %s\n',file);
end
