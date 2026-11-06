function bundle=review_sac_wind_history()
% Bounded frozen checkpoint review, with resumable delivery bundle.
% Run from a fresh R2024b MATLAB session. No training is launched.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; restore=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
receipt=fullfile(root,'artifacts','sac-weak-wind-1000-run.txt');
session=strtrim(fileread(receipt));
[~,id]=fileparts(session);
assert(strcmp(id,'20261105_210649_recovery_tpb199bcee'), ...
    'Review:Source','Unexpected weak-wind run receipt.');
model=jsondecode(fileread(fullfile(session,'model.json')));
assert(strcmp(model.name,'sac_paper64'),'Review:Model','Unexpected model.');
state=jsondecode(fileread(fullfile(session,'status.json')));
assert(strcmp(state.state,'paused'),'Review:Active','Review requires the paused run.');
trainingenv.resolve(session);
episodes=1000:100:1500; seeds=516:525;
bundle=fullfile(root,'artifacts','packages',['sac-wind-history-' id]);
if ~isfolder(bundle), mkdir(bundle); end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'), ...
    System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
manifestFile=fullfile(bundle,'manifest.json');
evaluatorHash=checkpointreview.sha256(fullfile(root,'compare_training_checkpoints.m'));
sourceFiles=["curriculum.json","model.json","environment.json","recovery.json"];
hashes=cell(size(sourceFiles));
for k=1:numel(sourceFiles)
    hashes{k}=checkpointreview.sha256(fullfile(session,sourceFiles(k)));
end
if isfile(manifestFile)
    manifest=jsondecode(fileread(manifestFile));
    assert(strcmp(manifest.session,session) && isequal(manifest.episodes(:),episodes(:)) && ...
        isequal(manifest.seeds(:),seeds(:)) && strcmp(manifest.evaluator_sha256,evaluatorHash) && ...
        isequal(string(manifest.source_hashes(:)),string(hashes(:))), ...
        'Review:Changed','Bundle belongs to different inputs.');
else
    manifest=struct('schema_version',1,'session',session,'episodes',episodes,'seeds',seeds, ...
        'stages',[1 2],'source_hashes',{hashes},'evaluator_sha256',evaluatorHash, ...
        'status','prepared','completed_episodes',[], ...
        'scope','Retrospective diagnostic routes already inspected; CPU, no exploration, 3000 step limit.');
    trainingcurriculum.write_json(manifestFile,manifest);
    for name=sourceFiles
        copyfile(fullfile(session,name),fullfile(bundle,name));
    end
end
% Check every checkpoint before spending time on simulations.
checkpointHashes=cell(size(episodes));
for k=1:numel(episodes)
    file=fullfile(session,'checkpoints',sprintf('Agent%d.mat',episodes(k)));
    checkpoint_select_agent(file);
    [~,actual]=checkpoint_resume_state(file);
    assert(actual==episodes(k),'Review:Episode','Checkpoint episode mismatch.');
    checkpointHashes{k}=checkpointreview.sha256(file);
end
manifest.status='running';
if isfield(manifest,'error'), manifest=rmfield(manifest,'error'); end
trainingcurriculum.write_json(manifestFile,manifest);
summaries={};
try
    for k=1:numel(episodes)
        ep=episodes(k);
        destination=fullfile(bundle,sprintf('episode_%d',ep));
        completedFile=fullfile(destination,'complete.json');
        if isfile(completedFile)
            saved=jsondecode(fileread(completedFile));
            assert(strcmp(saved.checkpoint_sha256,checkpointHashes{k}), ...
                'Review:Changed','Checkpoint changed since previous review.');
            for n=1:numel(saved.files)
                assert(strcmp(checkpointreview.sha256(fullfile(destination,saved.files(n).name)), ...
                    saved.files(n).sha256),'Review:Changed','Delivery file changed.');
            end
            report=jsondecode(fileread(fullfile(destination,'evaluation.json')));
            fprintf('Verified completed checkpoint %d; skipping simulation.\n',ep);
        else
            fprintf('Review %d/%d: checkpoint %d. Bundle: %s\n',k,numel(episodes),ep,bundle);
            report=compare_training_checkpoints(string(session),episodes=ep,includeLatest=false, ...
                stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
            assert(strcmp(report.status,'complete') && numel(report.results)==20 && ...
                strcmp(report.checkpoints{1}.sha256,checkpointHashes{k}), ...
                'Review:Incomplete','Unexpected evaluation result.');
            % Original evaluation remains available if copying is interrupted.
            if ~isfolder(destination), mkdir(destination); end
            copyfile(fullfile(report.outputDir,'*'),destination);
            files=dir(fullfile(destination,'*')); files=files(~[files.isdir]);
            inventory=struct('name',{},'sha256',{});
            for n=1:numel(files)
                inventory(n)=struct('name',files(n).name, ...
                    'sha256',checkpointreview.sha256(fullfile(destination,files(n).name)));
            end
            trainingcurriculum.write_json(completedFile, ...
                struct('checkpoint_sha256',checkpointHashes{k},'files',inventory));
        end
        rows=report.summary;
        if isstruct(rows), rows=num2cell(rows); end
        summaries=[summaries rows(:)']; %#ok<AGROW>
        trainingcurriculum.write_json(fullfile(bundle,'summary.json'),summaries);
        manifest.completed_episodes=episodes(1:k);
        trainingcurriculum.write_json(manifestFile,manifest);
    end
    manifest.status='complete';
    trainingcurriculum.write_json(manifestFile,manifest);
catch err
    manifest.status='failed';
    manifest.error=getReport(err,'extended','hyperlinks','off');
    trainingcurriculum.write_json(manifestFile,manifest);
    rethrow(err);
end
fprintf('All 120 flights complete. Delivery folder:\n%s\n',bundle);
end
