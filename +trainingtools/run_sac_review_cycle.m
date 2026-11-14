function bundle=run_sac_review_cycle()
% One remote, bounded review -> selection -> training -> final review cycle.
% Re-entry reuses verified evaluations; never relaunches a recorded launch.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; cleanup=onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
bundle=fullfile(root,'artifacts','packages','sac-review-cycle-20261114');
if ~isfolder(bundle), mkdir(bundle); end
lock=System.IO.File.Open(fullfile(bundle,'cycle.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
diary(fullfile(bundle,'cycle.log')); diaryGuard=onCleanup(@() diary('off')); %#ok<NASGU>
ledgerFile=fullfile(bundle,'cycle.json');
if isfile(ledgerFile)
    previous=read(ledgerFile);
    if any(strcmp(previous.phase,{'complete','no_candidate','holdout_failed','cancelled'}))
        fprintf('Cycle already finished. Packaging only; no further training.\n'); return;
    end
    assert(~isfield(previous,'launch_intent') || ~previous.launch_intent, ...
        'Review:Interrupted','A launch was recorded. Do not relaunch automatically; collect bundle and inspect child.');
    assert(~isfield(previous,'prepare_intent') || ~previous.prepare_intent, ...
        'Review:Interrupted','Preparation was recorded. Inspect the retained child before retrying.');
end
ledger=struct('schema_version',1,'phase','preflight','launch_intent',false, ...
    'prepare_intent',false,'child','','launches',0,'max_added_episodes',500);
write(ledgerFile,ledger);
try
    source=strtrim(fileread(fullfile(root,'artifacts','sac-wind-actor-half-1500-run.txt')));
    expected=fullfile(root,'experiments','sac_random_route_v1','runs','20261107_132924_recovery_tp578fea3e');
    assert(strcmpi(canonical(source),canonical(expected)),'Review:Source','Unexpected source receipt.');
    model=read(fullfile(source,'model.json')); state=read(fullfile(source,'status.json'));
    outcome=read(fullfile(source,'curriculum_outcome.json'));
    assert(strcmp(model.name,'sac_paper64') && strcmp(state.state,'paused') && outcome.episodes==2000 && ...
        strcmp(outcome.curriculumReason,'recovery_budget'),'Review:Source','Expected paused half-rate 2000 source.');
    trainingenv.resolve(source);
    cfg=read(fullfile(source,'control.json'));
    assert(model.actorLearnRate==1.5e-4 && model.criticLearnRate==3e-4 && ...
        strcmp(cfg.trainingDevice,'gpu') && strcmp(cfg.executionMode,'parallel') && ...
        cfg.numWorkers==6 && cfg.minWorkers==6 && cfg.checkpointEvery==100, ...
        'Review:Settings','Unexpected source model or execution settings.');
    capability=trainingtools.preflight_sac_random('gpu',6);
    write(fullfile(bundle,'capability.json'),capability);
    episodes=1500:100:2000;
    checkpointHashes=cell(size(episodes));
    for k=1:numel(episodes)
        file=fullfile(source,'checkpoints',sprintf('Agent%d.mat',episodes(k)));
        checkpoint_select_agent(file); [~,actual]=checkpoint_resume_state(file);
        assert(actual==episodes(k),'Review:Episode','Checkpoint history mismatch.');
        checkpointHashes{k}=checkpointreview.sha256(file);
    end
    % Above the training seed range (1..1e9); disjoint from original gate seeds.
    seeds=2000011401:2000011410; holdout=2000011501:2000011510;
    inputs=struct('source',source,'episodes',episodes,'seeds',seeds,'holdout',holdout, ...
        'checkpoint_hashes',{checkpointHashes}, ...
        'source_hashes',{hashes(source,{'curriculum.json','model.json','environment.json','recovery.json'})}, ...
        'code_hashes',{hashes(root,{'compare_training_checkpoints.m', ...
        '+checkpointreview/random_path.m','+trainingtools/run_sac_review_cycle.m', ...
        '+trainingtools/select_sac_review.m','+trainingtools/prepare_recovery_training.m', ...
        'runtime/training_engine.m','+trainingcurriculum/frozen_gate.m'})});
    inputFile=fullfile(bundle,'inputs.json');
    if isfile(inputFile)
        assert(isequaln(read(inputFile),jsondecode(jsonencode(inputs))), ...
            'Review:Changed','Inputs/code changed; do not reuse this cycle.');
    else, write(inputFile,inputs); end
    reports=cell(1,numel(episodes));
    ledger.source=source; ledger.phase='selection_evaluation'; write(ledgerFile,ledger);
    for k=1:numel(episodes)
        if isfile(fullfile(bundle,'CANCEL')), ledger.phase='cancelled'; write(ledgerFile,ledger); return; end
        reports{k}=evaluate(source,episodes(k),[1 2],seeds, ...
            fullfile(bundle,sprintf('selection_%d',episodes(k))),false);
    end
    decision=trainingtools.select_sac_review(reports,seeds,1500);
    write(fullfile(bundle,'selection.json'),decision);
    if isempty(decision.selected_episode)
        ledger.phase='no_candidate'; write(ledgerFile,ledger); return;
    end
    ep=decision.selected_episode;
    ledger.selected_episode=ep; ledger.phase='holdout'; write(ledgerFile,ledger);
    baseline=evaluate(source,1500,[1 2],holdout,fullfile(bundle,'holdout_1500'),false);
    if ep==1500, candidate=baseline;
    else, candidate=evaluate(source,ep,[1 2],holdout,fullfile(bundle,sprintf('holdout_%d',ep)),false); end
    if ep==1500, holdReports={baseline}; else, holdReports={baseline,candidate}; end
    validation=trainingtools.select_sac_review(holdReports,holdout,1500);
    chosen=validation.metrics([validation.metrics.episode]==ep);
    validation.chosen_episode=ep; validation.chosen_passed=chosen.eligible;
    write(fullfile(bundle,'holdout.json'),validation);
    if ~chosen.eligible
        ledger.phase='holdout_failed'; write(ledgerFile,ledger); return;
    end
    if isfile(fullfile(bundle,'CANCEL')), ledger.phase='cancelled'; write(ledgerFile,ledger); return; end
    assert(isequal(hashes(source,{'curriculum.json','model.json','environment.json','recovery.json'}),inputs.source_hashes), ...
        'Review:Changed','Source snapshots changed during review.');
    recipe=read(fullfile(root,'configs','sac_wind_actor_half_extend_1500.json'));
    recipe.pilot='sac_wind_review_selected'; recipe.expected_run='20261107_132924_recovery_tp578fea3e';
    recipe.checkpoint_episode=ep;
    recipe.expected_checkpoint_sha256=checkpointHashes{episodes==ep};
    assert(strcmp(recipe.expected_checkpoint_sha256,checkpointreview.sha256(fullfile(source,'checkpoints',sprintf('Agent%d.mat',ep)))), ...
        'Review:Changed','Selected checkpoint changed after review.');
    recipe.selection_evidence=struct('selection_sha256',checkpointreview.sha256(fullfile(bundle,'selection.json')), ...
        'holdout_sha256',checkpointreview.sha256(fullfile(bundle,'holdout.json')),'bundle',bundle);
    recipeFile=fullfile(bundle,'selected_recipe.json'); write(recipeFile,recipe);
    ledger.phase='prepare'; ledger.prepare_intent=true; write(ledgerFile,ledger);
    info=trainingtools.prepare_recovery_training(source,recipeFile);
    child=info.sessionDir; ledger.child=child; ledger.phase='prepared'; write(ledgerFile,ledger);
    write(fullfile(child,'review_cycle.json'),struct('bundle',bundle,'selected_episode',ep,'total_budget',500));
    % Every invocation starts one attempt only. A second invocation is permitted
    % solely after a genuine stage boundary with the original frozen gate passed.
    expectedStage=[];
    for launch=1:4
        if isfile(fullfile(bundle,'CANCEL')), ledger.phase='cancelled'; write(ledgerFile,ledger); return; end
        ledger.launch_intent=true; ledger.launches=launch; ledger.phase='training'; write(ledgerFile,ledger);
        info=retry(resume=string(child),start=true,maxAttempts=1);
        ledger.supervisor_pid=double(info.supervisor.Id); write(ledgerFile,ledger);
        fprintf('Training child: %s\nSupervisor PID: %d\n',child,info.supervisor.Id);
        heartbeat=tic;
        while ~info.supervisor.WaitForExit(1000)
            % CANCEL is observed after the current attempt; never kill training.
            if toc(heartbeat)>=60
                fprintf('Waiting for bounded training attempt %d. Child: %s\n',launch,child); heartbeat=tic;
            end
        end
        st=read(fullfile(child,'status.json'));
        assert(info.supervisor.ExitCode==0,'Review:Training','Supervisor failed; no retry.');
        ledger.last_status=st; write(ledgerFile,ledger);
        assert(strcmp(st.state,'paused') || strcmp(st.state,'success'), ...
            'Review:Training','Training did not finish normally; no automatic retry.');
        attempts=dir(fullfile(child,'attempt_*')); attempts=attempts([attempts.isdir]);
        [~,order]=sort({attempts.name}); attempt=fullfile(child,attempts(order(end)).name);
        result=read(fullfile(attempt,'result.json'));
        workers=readtable(fullfile(child,'diagnostics','worker_attempts.csv'));
        assert(workers.ExitCode(end)==0,'Review:Training','Nonzero attempt exit; no retry.');
        actualState=read(fullfile(child,'curriculum_state.json'));
        assert(isempty(expectedStage) || actualState.stage_index==expectedStage, ...
            'Review:Transition','Expected curriculum transition did not occur; do not retry.');
        ledger.saved_episode=result.episodes; ledger.added_episodes=result.episodes-ep;
        ledger.training_stop_reason=result.curriculumReason;
        assert(ledger.added_episodes>=0 && ledger.added_episodes<=500, ...
            'Review:Budget','Unexpected total episode count.');
        write(ledgerFile,ledger);
        if isfile(fullfile(bundle,'CANCEL')), ledger.phase='cancelled'; break; end
        if result.success || isfield(result,'pauseReason'), break; end
        if ~any(strcmp(result.curriculumReason,{'conditions_met','frozen_evaluation_required'})), break; end
        [passed,gate]=stageGate(child,result,fullfile(bundle,sprintf('gate_%d',launch)));
        write(fullfile(bundle,sprintf('gate_%d.json',launch)),gate);
        if ~passed || ledger.added_episodes>=500, break; end
        guard=read(fullfile(child,'training_guard_state.json'));
        assert(~guard.paused,'Review:Guard','Never unlock a paused guard.');
        ledger.phase='gate_passed'; write(ledgerFile,ledger);
        expectedStage=gate.next_stage_index;
        % Next retry calls curriculum.prepare, which performs the transition.
        % Do not edit curriculum_state, outcome, guard, or any source snapshot.
    end
    ledger.phase='final_evaluation'; write(ledgerFile,ledger);
    if isfile(fullfile(child,'Agent_Final.mat'))
        [history,savedEpisode]=checkpoint_resume_state(fullfile(child,'Agent_Final.mat'));
        assert(savedEpisode==ledger.saved_episode,'Review:Episode','Final model and attempt disagree.');
        windows=struct('first',{},'last',{},'count',{},'mean_reward',{},'mean_steps',{},'full_count',{});
        for first=ep+1:100:savedEpisode
            last=min(first+99,savedEpisode); ix=first:last;
            windows(end+1)=struct('first',first,'last',last,'count',numel(ix), ...
                'mean_reward',mean(history.EpisodeReward(ix)),'mean_steps',mean(history.EpisodeSteps(ix)), ...
                'full_count',sum(history.EpisodeSteps(ix)>=3000)); %#ok<AGROW>
        end
        write(fullfile(bundle,'training_summary.json'),struct('origin_episode',ep,'saved_episode',savedEpisode, ...
            'added_episodes',savedEpisode-ep,'new_steps',sum(history.EpisodeSteps(ep+1:end)), ...
            'windows',windows,'scope','Training statistics; not frozen controller performance.'));
    end
    if isfile(fullfile(child,'Agent_Final.mat')) && ~isfile(fullfile(bundle,'CANCEL'))
        current=read(fullfile(child,'curriculum_state.json'));
        evaluate(child,[],unique([1 2 current.stage_index]),holdout,fullfile(bundle,'final_evaluation'),true);
    end
    ledger.final_state=read(fullfile(child,'curriculum_state.json'));
    ledger.final_outcome=read(fullfile(child,'curriculum_outcome.json'));
    ledger.phase='complete';
    if isfile(fullfile(bundle,'CANCEL')), ledger.phase='cancelled'; end
    write(ledgerFile,ledger);
catch err
    ledger.phase='failed'; ledger.error=getReport(err,'extended','hyperlinks','off');
    write(ledgerFile,ledger); rethrow(err);
end
fprintf('Review cycle finished: %s\n',bundle);
end

function r=evaluate(session,ep,stages,seeds,destination,final)
if final, checkpoint=fullfile(session,'Agent_Final.mat');
else, checkpoint=fullfile(session,'checkpoints',sprintf('Agent%d.mat',ep)); end
hash=checkpointreview.sha256(checkpoint);
done=fullfile(destination,'complete.json');
if isfile(done)
    saved=read(done);
    assert(strcmp(saved.checkpoint_sha256,hash) && isequal(saved.seeds(:),seeds(:)) && ...
        isequal(saved.stages(:),stages(:)),'Review:Changed','Evaluation inputs changed.');
    for k=1:numel(saved.files)
        assert(strcmp(checkpointreview.sha256(fullfile(destination,saved.files(k).name)),saved.files(k).sha256), ...
            'Review:Changed','Evaluation bundle corrupted.');
    end
    r=read(fullfile(destination,'evaluation.json')); return;
end
fprintf('Frozen review %s, checkpoint %s; %d flights.\n',session,checkpoint,numel(stages)*numel(seeds));
r=compare_training_checkpoints(string(session),episodes=ep,includeLatest=false,finalCheckpoint=final, ...
    stages=stages,seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
assert(strcmp(r.status,'complete') && r.weights_unchanged && ...
    numel(r.results)==numel(stages)*numel(seeds),'Review:Report','Incomplete evaluation.');
if ~isfolder(destination), mkdir(destination); end
copyfile(fullfile(r.outputDir,'*'),destination);
files=dir(fullfile(destination,'*')); files=files(~[files.isdir]);
inventory=struct('name',{},'sha256',{});
for k=1:numel(files)
    if strcmp(files(k).name,'complete.json'), continue; end
    inventory(end+1)=struct('name',files(k).name,'sha256',checkpointreview.sha256(fullfile(destination,files(k).name))); %#ok<AGROW>
end
write(done,struct('checkpoint_sha256',hash,'stages',stages,'seeds',seeds,'files',inventory));
end

function [passed,result]=stageGate(child,outcome,destination)
plan=trainingcurriculum.load_plan(fullfile(child,'curriculum.json'),true);
state=read(fullfile(child,'curriculum_state.json')); stage=plan.stages{state.stage_index};
assert(state.stage_index==outcome.stageIndex && isfield(stage,'frozen_gate'), ...
    'Review:Stage','Unexpected stage or missing frozen gate.');
evaluate(child,[],unique([1 state.stage_index]),stage.frozen_gate.seeds(:)',destination,true);
context=struct('sessionDir',child,'stage',stage,'state',state);
passed=trainingcurriculum.frozen_gate(context,fullfile(child,'Agent_Final.mat'));
result=struct('passed',passed,'stage_index',state.stage_index,'episode',outcome.episodes, ...
    'next_stage_index',min(state.stage_index+1,numel(plan.stages)), ...
    'scope','Original curriculum frozen gate; state transition occurs only in curriculum.prepare.');
end
function h=hashes(root,names)
h=cell(size(names));
for k=1:numel(names), h{k}=checkpointreview.sha256(fullfile(root,names{k})); end
end
function p=canonical(p)
assert(java.io.File(p).isAbsolute(),'Review:Path','Receipt must contain an absolute path.');
p=char(java.io.File(p).getCanonicalPath());
end
function value=read(file), value=jsondecode(fileread(file)); end
function write(file,value), trainingcurriculum.write_json(file,value); end
