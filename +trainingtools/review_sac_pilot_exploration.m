function bundle=review_sac_pilot_exploration()
% Bounded frozen-policy experiment: three agents x four routes x two stages.
% Existing deterministic results are reused; no training, pool or stage change.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
pilot=fullfile(root,'artifacts','packages','sac-actor-pilot-20261116');
bundle=fullfile(root,'artifacts','packages','sac-pilot-exploration-20261117');
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
ledgerFile=fullfile(bundle,'review.json');
if isfile(ledgerFile)
    previous=read(ledgerFile);
    if strcmp(previous.status,'complete'),fprintf('Already complete; package only.\n');return;end
    assert(~isfield(previous,'simulation_started') || ~previous.simulation_started, ...
        'ExplorationReview:Interrupted','A simulation was already requested. Package and inspect; do not repeat automatically.');
end
state=struct('status','preflight','simulation_started',false,'completed',{{}});
write(ledgerFile,state);
try
    prior=read(fullfile(pilot,'review.json'));assert(strcmp(prior.status,'complete'),'ExplorationReview:Pilot','Complete pilot required.');
    protocol=read(fullfile(pilot,'protocol.json'));
    children=prior.children;if iscell(children),children=[children{:}];end
    seeds=[2000011504 2000011507 2000011601 2000011602];
    labels={'reference1600','baseline','actor_half'};
    protocolOut=struct('route_seeds',seeds,'stages',[1 2],'new_simulations_max',24, ...
        'max_steps_per_simulation',3000,'exploration_std_scale',1, ...
        'scope','Failure-selected diagnostic routes, not holdout/generalization. One sampled rollout per route/stage/model. MATLAB RNG seed matched; not independent turbulence timing.', ...
        'question','Does sampling the frozen policy recover failed deterministic flights? No learning or automatic follow-on training.');
    write(fullfile(bundle,'protocol.json'),protocolOut);
    sessions=cell(1,3);offReports=cell(1,3);expected=cell(1,3);
    for k=1:3
        if k==1
            remote=protocol.source;folder='reference1600';
        else
            item=children(strcmp({children.label},labels{k}));assert(numel(item)==1);
            remote=item.session;folder=[labels{k} '_evaluation'];
        end
        parts=regexp(remote,'[\\/]','split');id=parts{end};
        assert(~isempty(regexp(id,'^202611[0-9]{2}_\d{6}_recovery_tp[0-9a-f]+$','once')), ...
            'ExplorationReview:Path','Unexpected run identity.');
        sessions{k}=fullfile(root,'experiments','sac_random_route_v1','runs',id);
        s=read(fullfile(sessions{k},'status.json'));m=read(fullfile(sessions{k},'model.json'));
        assert(strcmp(s.state,'paused') && strcmp(m.name,'sac_paper64'),'ExplorationReview:Source','Expected paused paper64.');
        r=read(fullfile(pilot,folder,'evaluation.json'));cp=r.checkpoints;if iscell(cp),cp=[cp{:}];end
        assert(numel(cp)==1 && cp.episode==1600+100*(k>1),'ExplorationReview:Checkpoint','Wrong episode.');
        if k==1,file=fullfile(sessions{k},'checkpoints','Agent1600.mat');else,file=fullfile(sessions{k},'Agent_Final.mat');end
        expected{k}=cp.sha256;
        assert(strcmp(checkpointreview.sha256(file),expected{k}),'ExplorationReview:Changed','Evaluated model changed.');
        validate(r,false,seeds,false);offReports{k}=r;
        target=fullfile(bundle,labels{k});if ~isfolder(target),mkdir(target);end
        copyfile(fullfile(pilot,folder,'evaluation.json'),fullfile(target,'off_evaluation.json'));
    end
    comparison={};
    for k=1:3
        state.status='simulating';state.simulation_started=true;state.current=labels{k};write(ledgerFile,state);
        ep=[];if k==1,ep=1600;end
        r=compare_training_checkpoints(string(sessions{k}),episodes=ep,includeLatest=false, ...
            finalCheckpoint=k>1,stages=[1 2],seeds=seeds,maxSteps=3000, ...
            useExploration=true,explorationStdScale=1,routeMetrics=true);
        validate(r,true,seeds,true);
        cp=r.checkpoints;if iscell(cp),cp=[cp{:}];end
        assert(numel(cp)==1 && strcmp(cp.sha256,expected{k}),'ExplorationReview:Changed','Wrong evaluated checkpoint.');
        off=offReports{k};
        for field={'curriculum_sha256','model_sha256','runtime_sha256','random_path_sha256','guidance_variant'}
            assert(strcmp(off.(field{1}),r.(field{1})),'ExplorationReview:Environment','Evaluation environment changed.');
        end
        target=fullfile(bundle,labels{k},'on');if ~isfolder(target),mkdir(target);end
        copyfile(fullfile(r.outputDir,'*'),target);
        a=rows(off);b=rows(r);
        for j=1:numel(b)
            x=b(j);y=a([a.seed]==x.seed & strcmp({a.stage_id},x.stage_id));assert(numel(y)==1);
            assert(isequal([x.wind_east_mps x.wind_north_mps x.turbulence], ...
                [y.wind_east_mps y.wind_north_mps y.turbulence]),'ExplorationReview:Wind','Wind pairing differs.');
            comparison{end+1}=struct('arm',labels{k},'seed',x.seed,'stage',x.stage_id, ...
                'off_steps',y.steps,'on_steps',x.steps,'off_reward',y.reward,'on_reward',x.reward, ...
                'off_full',y.steps==3000 && ~y.environment_done, ...
                'on_full',x.steps==3000 && ~x.environment_done, ...
                'off_end',y.termination_evidence,'on_end',x.termination_evidence); %#ok<AGROW>
        end
        state.completed{end+1}=labels{k};write(fullfile(bundle,'comparison.json'),comparison);write(ledgerFile,state);
    end
    state.status='complete';write(ledgerFile,state);
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');write(ledgerFile,state);rethrow(err);
end
fprintf('Exploration comparison complete. No training. Keep all runs paused.\n');
end
function validate(r,exploration,seeds,exact)
assert(strcmp(r.status,'complete') && r.weights_unchanged && r.use_exploration==exploration && ...
    r.exploration_std_scale==1 && r.max_steps==3000 && r.route_metrics_enabled && ...
    strcmp(r.guidance_variant,'baseline'),'ExplorationReview:Report','Unexpected report semantics.');
a=rows(r);if exact,assert(numel(a)==8,'ExplorationReview:Count','Expected eight simulations.');end
for stage={'random_calm','random_weak_wind'}
    for seed=seeds
        assert(sum([a.seed]==seed & strcmp({a.stage_id},stage{1}))==1,'ExplorationReview:Pairs','Missing or duplicate pair.');
    end
end
end
function a=rows(r),a=r.results;if iscell(a),a=[a{:}];end,end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
