function batch = review_stage6_checkpoints(sessionDir)
% Compare the paused spatial-route run; no training or checkpoint changes.
% Requires the reward-audit evaluator. Results remain in the run's reports/.
arguments
    sessionDir (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));
expected='495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be';
assert(strcmpi(checkpointreview.sha256(fullfile(root,'runtime','FAFA_Simulation.slx')),expected), ...
    'Stage6Review:Environment','Runtime differs from the spatial-route environment. Do not mix evaluation versions.');
if ~java.io.File(char(sessionDir)).isAbsolute()
    sessionDir=fullfile(root,sessionDir);
end
episodes=[31600 33700 41600];
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(any(strcmp(status.state,{'paused','stopped','success','error'})), ...
    'Stage6Review:Active','Session must be stopped before evaluation.');
for ep=episodes
    f=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep));
    assert(isfile(f),'Stage6Review:Missing','Missing checkpoint: %s',f);
end
assert(~bdIsLoaded('FAFA_Simulation'),'Stage6Review:ModelLoaded', ...
    'Close FAFA_Simulation before evaluation; do not discard unsaved edits.');
[~,tag]=fileparts(tempname);
out=fullfile(sessionDir,'reports',"stage6_review_"+ ...
    string(datetime('now','Format','yyyyMMdd_HHmmss'))+"_"+string(tag));
mkdir(out);
batch=struct('status','running','session',char(sessionDir), ...
    'episodes',episodes,'outputDir',char(out), ...
    'scope','Paired CPU simulation; not training or a qualification certificate.');
saveManifest();
fprintf('45 simulations planned: 30 stage-6, 6 reward detail, 9 retention.\n');
try
    paired=compare_training_checkpoints(sessionDir,episodes=episodes, ...
        includeLatest=false,stages=6,seeds=201:210);
    batch.paired=paired.outputDir;
    copyfile(fullfile(paired.outputDir,'evaluation.json'),fullfile(out,'paired.json'));
    saveManifest();
    detail=compare_training_checkpoints(sessionDir,episodes=episodes, ...
        includeLatest=false,stages=6,seeds=[202 205],rewardDiagnostics=true);
    batch.detail=detail.outputDir;saveManifest();
    trainingtools.audit_training_rewards(detail.outputDir);
    copyfile(fullfile(detail.outputDir,'evaluation.json'),fullfile(out,'detail.json'));
    copyfile(fullfile(detail.outputDir,'reward_breakdown.json'),fullfile(out,'reward_breakdown.json'));
    saveManifest();
    retention=compare_training_checkpoints(sessionDir,episodes=episodes, ...
        includeLatest=false,stages=[1 2 3],seeds=101);
    batch.retention=retention.outputDir;
    copyfile(fullfile(retention.outputDir,'evaluation.json'),fullfile(out,'retention.json'));
    batch.status='complete';saveManifest();
catch err
    batch.status='failed';batch.error_identifier=err.identifier;
    batch.error_message=err.message;saveManifest();
    fprintf(2,'Partial results retained at: %s\n',out);
    rethrow(err);
end
% Share compact JSON only. Detailed MAT traces remain in evaluation folders.
zipPath=char(out+".zip");
zip(zipPath,{'batch.json','paired.json','detail.json', ...
    'reward_breakdown.json','retention.json'},char(out));
batch.summaryZip=zipPath;saveManifest();
fprintf('\nSummary ZIP: %s\nDetailed traces retained locally. No training started.\n',zipPath);
disp(paired.summary);
    function saveManifest()
        f=fullfile(out,'batch.json');
        fid=fopen(f,'w','n','UTF-8');assert(fid~=-1,'Stage6Review:Write','Cannot write %s',f);
        cleanup=onCleanup(@()fclose(fid));
        fprintf(fid,'%s',jsonencode(batch,PrettyPrint=true));
    end
end
