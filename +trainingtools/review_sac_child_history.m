function bundle=review_sac_child_history()
% Frozen diagnosis of ONE child; no selection, retry, training or stage edits.
root=fileparts(fileparts(mfilename('fullpath')));
old=path; restore=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
session=fullfile(root,'experiments','sac_random_route_v1','runs','20261114_211021_recovery_tp4c32126b');
bundle=fullfile(root,'artifacts','packages','sac-child-history-20261116');
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
diary(fullfile(bundle,'review.log'));finish=onCleanup(@() diary('off')); %#ok<NASGU>
ledger=struct('status','preflight','session',session,'completed_episodes',[], ...
    'scope','Frozen diagnosis only; no training, automatic continuation or stage transition.');
try
    state=read(fullfile(session,'status.json'));model=read(fullfile(session,'model.json'));
    outcome=read(fullfile(session,'curriculum_outcome.json'));lineage=read(fullfile(session,'recovery.json'));
    assert(strcmp(state.state,'paused') && strcmp(model.name,'sac_paper64') && ...
        outcome.episodes==2100 && strcmp(outcome.curriculumReason,'recovery_budget') && ...
        lineage.parent_episode==1600,'ChildReview:Source','Unexpected child state or lineage.');
    [~,parentId]=fileparts(lineage.parent_session);
    assert(strcmp(parentId,'20261107_132924_recovery_tp578fea3e'),'ChildReview:Source','Wrong parent.');
    [env,~]=trainingenv.resolve(session);
    episodes=1600:100:2100; seeds=2000011501:2000011510;
    files=cell(1,6); sha=cell(1,6);
    for k=1:6
        files{k}=fullfile(session,'checkpoints',sprintf('Agent%d.mat',episodes(k)));
        if k==6,files{k}=fullfile(session,'Agent_Final.mat');end
        checkpoint_select_agent(files{k});[~,ep]=checkpoint_resume_state(files{k});
        assert(ep==episodes(k),'ChildReview:Episode','Checkpoint history mismatch.');
        sha{k}=checkpointreview.sha256(files{k});
    end
    assert(strcmp(sha{1},lineage.parent_sha256),'ChildReview:Source','Initial checkpoint changed.');
    expected=struct('curriculum_sha256',checkpointreview.sha256(fullfile(session,'curriculum.json')), ...
        'model_sha256',checkpointreview.sha256(env), ...
        'runtime_sha256',checkpointreview.sha256(fullfile(root,'runtime','training_engine.m')), ...
        'random_path_sha256',checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m')));
    inputs=struct('session',session,'episodes',episodes,'seeds',seeds,'checkpoint_sha256',{sha}, ...
        'expected',expected,'evaluator_sha256',checkpointreview.sha256(fullfile(root,'compare_training_checkpoints.m')));
    inputFile=fullfile(bundle,'inputs.json');
    if isfile(inputFile)
        assert(isequaln(read(inputFile),jsondecode(jsonencode(inputs))),'ChildReview:Changed','Inputs changed.');
    else,write(inputFile,inputs);end
    for name=["status.json","model.json","curriculum.json","environment.json","recovery.json","training_guard_state.json"]
        copyfile(fullfile(session,name),fullfile(bundle,name));
    end
    cycle=fullfile(root,'artifacts','packages','sac-review-cycle-20261114');
    summaries={};ledger.status='running';write(fullfile(bundle,'review.json'),ledger);
    for k=1:6
        if isfile(fullfile(bundle,'CANCEL')),ledger.status='cancelled';break;end
        ep=episodes(k);destination=fullfile(bundle,sprintf('episode_%d',ep));
        cached=fullfile(destination,'complete.json');origin='new_evaluation';
        if isfile(cached)
            verify(destination,sha{k});r=read(fullfile(destination,'evaluation.json'));origin='verified_cache';
        else
            reuse='';
            if ep==1600,reuse=fullfile(cycle,'holdout_1600');end
            if ep==2100,reuse=fullfile(cycle,'final_evaluation');end
            if ~isempty(reuse) && isfile(fullfile(reuse,'complete.json'))
                verify(reuse,sha{k});r=read(fullfile(reuse,'evaluation.json'));origin='prior_cycle';from=reuse;
            else
                fprintf('Frozen checkpoint %d (%d/6): 20 flights, no training.\n',ep,k);
                if ep==2100
                    r=compare_training_checkpoints(string(session),episodes=[],includeLatest=false,finalCheckpoint=true, ...
                        stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
                else
                    r=compare_training_checkpoints(string(session),episodes=ep,includeLatest=false, ...
                        stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
                end
                from=r.outputDir;
            end
            validate(r,ep,seeds,sha{k},expected);
            if ~isfolder(destination),mkdir(destination);end
            copyfile(fullfile(from,'*'),destination);
            inventory=dir(fullfile(destination,'*'));inventory=inventory(~[inventory.isdir]);items=struct('name',{},'sha256',{});
            for n=1:numel(inventory)
                if strcmp(inventory(n).name,'complete.json'),continue;end
                items(end+1)=struct('name',inventory(n).name,'sha256',checkpointreview.sha256(fullfile(destination,inventory(n).name))); %#ok<AGROW>
            end
            write(cached,struct('checkpoint_sha256',sha{k},'files',items,'origin',origin));
        end
        validate(r,ep,seeds,sha{k},expected);
        assert(strcmp(sha{k},checkpointreview.sha256(files{k})),'ChildReview:Changed','Source changed.');
        summary=trainingtools.select_sac_review({r},seeds,ep); % validation/counts only; NEVER launches its selection
        row=summary.metrics;row.origin=origin;
        row=rmfield(row,'eligible');summaries{end+1}=row; %#ok<AGROW>
        write(fullfile(bundle,'summary.json'),summaries);
        ledger.completed_episodes=episodes(1:k);write(fullfile(bundle,'review.json'),ledger);
        fprintf('Checkpoint %d complete (%s).\n',ep,origin);
    end
    if numel(ledger.completed_episodes)==6,ledger.status='complete';end
    write(fullfile(bundle,'review.json'),ledger);
catch err
    ledger.status='failed';ledger.error=getReport(err,'extended','hyperlinks','off');
    write(fullfile(bundle,'review.json'),ledger);rethrow(err);
end
end
function validate(r,ep,seeds,sha,expected)
assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && r.max_steps==3000 && ...
    r.route_metrics_enabled && strcmp(r.guidance_variant,'baseline'),'ChildReview:Report','Invalid frozen report.');
c=r.checkpoints;if iscell(c),c=[c{:}];end
assert(numel(c)==1 && c.episode==ep && strcmp(c.sha256,sha),'ChildReview:Report','Checkpoint mismatch.');
for key=string(fieldnames(expected))'
    assert(strcmp(r.(key),expected.(key)),'ChildReview:Report','Environment/evaluator mismatch.');
end
trainingtools.select_sac_review({r},seeds,ep); % checks unique paired rows, completeness and finite steps/wind
end
function verify(folder,sha)
s=read(fullfile(folder,'complete.json'));
assert(strcmp(s.checkpoint_sha256,sha),'ChildReview:Changed','Cached checkpoint changed.');
names=string({s.files.name});assert(any(names=="evaluation.json"),'ChildReview:Changed','Missing report inventory.');
for k=1:numel(s.files)
    name=s.files(k).name;assert(~contains(name,{'/','\','..'}),'ChildReview:Changed','Invalid inventory name.');
    assert(strcmp(checkpointreview.sha256(fullfile(folder,name)),s.files(k).sha256), ...
        'ChildReview:Changed','Cached delivery file changed.');
end
end
function r=read(file),r=jsondecode(fileread(file));end
function write(file,r),trainingcurriculum.write_json(file,r);end
