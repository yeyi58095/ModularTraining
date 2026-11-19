function bundle=review_sac_replay_holdout()
% Frozen new-route comparison only. No training or stage mutation.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
prior=fullfile(root,'artifacts','packages','sac-replay-replication-20261118');
bundle=fullfile(root,'artifacts','packages','sac-replay-holdout-20261119');
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledger=fullfile(bundle,'review.json');
if isfile(ledger)
    previous=read(ledger);
    if any(strcmp(previous.status,{'complete','cancelled'})),fprintf('Already finished; package only.\n');return;end
    assert(~previous.simulation_started,'ReplayHoldout:Interrupted','Simulation already requested; package evidence, do not repeat automatically.');
end
state=struct('status','preflight','simulation_started',false,'completed',{{}});write(ledger,state);
try
    p=read(fullfile(prior,'review.json'));screen=read(fullfile(prior,'screening.json'));
    assert(strcmp(p.status,'complete') && screen.screen_pass,'ReplayHoldout:Prior','Completed passing replication required.');
    ids={'20261114_211021_recovery_tp4c32126b','20261119_004245_recovery_tpf24d3776'};
    labels={'reference1600','retained500k'};folders={'reference1600','retained500k_evaluation'};
    hashes={'45e57ddc78b26a0f176aaf6703d1c21afb7838842b8cdd221a91718b1eb2d94c', ...
        'a08df5008415b6088c784e9501a59dfa5c3b3ae79340fc4e0fc826bc7d026fe6'};
    seeds=2000011901:2000011920;reports=cell(1,2);sessions=cell(1,2);
    protocol=struct('labels',{labels},'run_ids',{ids},'checkpoint_sha256',{hashes}, ...
        'seeds',seeds,'stages',[1 2],'max_simulations',80,'max_steps',3000, ...
        'use_exploration',false,'automatic_continuation',false, ...
        'scope','New routes relative to the two replay pilots; candidate selected using earlier routes. One rollout per route/stage; not independent wind timing or a generalization proof. No training or stage qualification.');
    write(fullfile(bundle,'protocol.json'),protocol);
    for k=1:2
        sessions{k}=fullfile(root,'experiments','sac_random_route_v1','runs',ids{k});
        s=read(fullfile(sessions{k},'status.json'));m=read(fullfile(sessions{k},'model.json'));
        assert(strcmp(s.state,'paused') && strcmp(m.name,'sac_paper64'),'ReplayHoldout:Source','Expected paused SAC paper64.');
        file=fullfile(sessions{k},'Agent_Final.mat');if k==1,file=fullfile(sessions{k},'checkpoints','Agent1600.mat');end
        assert(strcmp(checkpointreview.sha256(file),hashes{k}),'ReplayHoldout:Hash','Checkpoint changed.');
        reports{k}=read(fullfile(prior,folders{k},'evaluation.json'));
        a=rows(reports{k});assert(~any(ismember([a.seed],seeds)),'ReplayHoldout:Seeds','Routes already used in replication.');
    end
    comparison={};reference=[];
    for k=1:2
        if isfile(fullfile(bundle,'CANCEL')),state.status='cancelled';write(ledger,state);return;end
        state.status='evaluating';state.simulation_started=true;state.current=labels{k};write(ledger,state);
        ep=[];if k==1,ep=1600;end
        r=compare_training_checkpoints(string(sessions{k}),episodes=ep,includeLatest=false, ...
            finalCheckpoint=k==2,stages=[1 2],seeds=seeds,maxSteps=3000,useExploration=false,routeMetrics=true);
        assert(strcmp(r.status,'complete') && r.weights_unchanged && ~r.use_exploration && r.max_steps==3000,'ReplayHoldout:Evaluation','Incomplete evaluation.');
        cp=r.checkpoints;if iscell(cp),cp=[cp{:}];end
        assert(numel(cp)==1 && cp.episode==1600+100*(k==2) && strcmp(cp.sha256,hashes{k}),'ReplayHoldout:Hash','Wrong evaluated checkpoint.');
        for key={'curriculum_sha256','model_sha256','runtime_sha256','random_path_sha256','guidance_variant'}
            assert(strcmp(r.(key{1}),reports{k}.(key{1})),'ReplayHoldout:Environment','Environment differs from prior evaluation.');
            if k==2,assert(strcmp(r.(key{1}),reference.(key{1})),'ReplayHoldout:Environment','Pair environment differs.');end
        end
        a=rows(r);assert(numel(a)==40,'ReplayHoldout:Rows','Expected 40 flights.');
        for stage={'random_calm','random_weak_wind'}
            x=a(strcmp({a.stage_id},stage{1}));assert(isequal(sort([x.seed]),seeds),'ReplayHoldout:Rows','Missing/duplicate routes.');
            d=arrayfun(@(v) v.route_metrics.after_10_seconds,x);assert(all(isfinite([d.rms_m])) && all(isfinite([d.max_m])),'ReplayHoldout:Metrics','Missing distance metrics.');
            full=[x.steps]==3000 & ~[x.environment_done];
            comparison{end+1}=struct('arm',labels{k},'stage',stage{1},'seed_group',1,'count',20, ...
                'full_count',sum(full),'mean_steps',mean([x.steps]),'late_rms_mean_m',mean([d.rms_m]), ...
                'late_max_m',max([d.max_m]),'full_and_rms10_max20_count',sum(full & [d.rms_m]<=10 & [d.max_m]<=20), ...
                'actual_wind_count',sum([x.wind_east_mps]~=0 | [x.wind_north_mps]~=0 | [x.turbulence]~=0), ...
                'actual_wind_full',sum(full & ([x.wind_east_mps]~=0 | [x.wind_north_mps]~=0 | [x.turbulence]~=0))); %#ok<AGROW>
        end
        if k==1,reference=r;else
            b=rows(reference);
            for j=1:numel(a)
                y=b([b.seed]==a(j).seed & strcmp({b.stage_id},a(j).stage_id));
                assert(numel(y)==1 && isequal([y.wind_east_mps y.wind_north_mps y.turbulence], ...
                    [a(j).wind_east_mps a(j).wind_north_mps a(j).turbulence]),'ReplayHoldout:Wind','Wind pairing differs.');
            end
        end
        target=fullfile(bundle,labels{k});mkdir(target);copyfile(fullfile(r.outputDir,'*'),target);
        state.completed{end+1}=labels{k};write(fullfile(bundle,'comparison.json'),comparison);write(ledger,state);
    end
    state.status='complete';write(ledger,state);
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');write(ledger,state);rethrow(err);
end
fprintf('New-route review complete. No training; keep both runs paused.\n');
end
function a=rows(r),a=r.results;if iscell(a),a=[a{:}];end,end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
