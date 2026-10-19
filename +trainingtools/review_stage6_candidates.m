function batch=review_stage6_candidates(sessionDir)
% Additional paired scenarios for 33700/41600. No training or guard changes.
arguments
    sessionDir (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));
expected='495afb97a9fa463b4500d168909ea28f649a12912f12c0631ec1e85b93c1b6be';
assert(strcmpi(checkpointreview.sha256(fullfile(root,'runtime','FAFA_Simulation.slx')),expected), ...
    'CandidateReview:Environment','Unexpected runtime environment.');
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(any(strcmp(status.state,{'paused','stopped','success','error'})), ...
    'CandidateReview:Active','Keep training stopped during review.');
for ep=[33700 41600]
    f=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep));
    assert(isfile(f),'CandidateReview:Missing','Missing checkpoint: %s',f);
end
assert(~bdIsLoaded('FAFA_Simulation'),'CandidateReview:ModelLoaded', ...
    'Close FAFA_Simulation before evaluation; preserve any unsaved edits.');
[~,tag]=fileparts(tempname);
out=fullfile(sessionDir,'reports',"candidate_review_"+ ...
    string(datetime('now','Format','yyyyMMdd_HHmmss'))+"_"+string(tag));mkdir(out);
batch=struct('status','running','session',char(sessionDir),'episodes',[33700 41600], ...
    'seeds',401:420,'stages',[4 5 6],'outputDir',char(out),'evaluations',{{}}, ...
    'scope','120 paired CPU simulations. Fixed turbulence model seeds; not a qualification certificate.');
saveManifest();
fprintf('120 simulations: 2 checkpoints x 3 stages x 20 seeds. Position-only diagnostics.\n');
try
    for stage=4:6
        result=compare_training_checkpoints(sessionDir,episodes=[33700 41600], ...
            includeLatest=false,stages=stage,seeds=401:420,routeMetrics=true);
        batch.evaluations{end+1}=result.outputDir;
        copyfile(fullfile(result.outputDir,'evaluation.json'),fullfile(out,sprintf('stage%d.json',stage)));
        saveManifest();
    end
    batch.status='complete';batch.summaryZip=char(out+".zip");saveManifest();
    zip(batch.summaryZip,{'batch.json','stage4.json','stage5.json','stage6.json'},char(out));
catch err
    batch.status='failed';batch.error_identifier=err.identifier;batch.error_message=err.message;
    saveManifest();fprintf(2,'Partial results retained: %s\n',out);rethrow(err);
end
fprintf('Summary ZIP: %s\nNo training started.\n',batch.summaryZip);
    function saveManifest()
        fid=fopen(fullfile(out,'batch.json'),'w','n','UTF-8');
        assert(fid~=-1,'CandidateReview:Write','Cannot write batch manifest.');
        cleanup=onCleanup(@()fclose(fid));
        fprintf(fid,'%s',jsonencode(batch,PrettyPrint=true));
    end
end
