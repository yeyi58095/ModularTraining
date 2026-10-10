function report = compare_training_checkpoints(sessionDir,opt)
% Read-only, serial CPU evaluation of stopped curriculum checkpoints.
% No train(), checkpoint replacement, curriculum transition or automatic resume.
arguments
    sessionDir (1,1) string
    opt.episodes (1,:) double {mustBeInteger,mustBePositive} = [6100 10600]
    opt.includeLatest (1,1) logical = true
    opt.stages (1,:) double {mustBeInteger,mustBePositive} = [1 2 3]
    opt.seeds (1,:) double {mustBeInteger,mustBeNonnegative} = 101
    opt.maxSteps (1,1) double {mustBeInteger,mustBePositive} = 3000
end
root=fileparts(mfilename('fullpath')); runtime=fullfile(root,'runtime');
oldPath=path; oldFolder=pwd; oldRng=rng;
restore=onCleanup(@() restoreCaller(oldPath,oldFolder,oldRng)); %#ok<NASGU>
addpath(root,runtime);
% Resolve these before Simulink/model callbacks can change the MATLAB path.
writeReport=@trainingcurriculum.write_json;
failEvaluation=@checkpointreview.fail_evaluation;
if ~java.io.File(char(sessionDir)).isAbsolute(), sessionDir=fullfile(root,sessionDir); end
sessionDir=string(char(java.io.File(char(sessionDir)).getCanonicalPath()));
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(any(strcmp(status.state,{'stopped','paused','success','error'})), ...
    'Evaluation:Active','Stop training before evaluation.');
assert(~bdIsLoaded('FAFA_Simulation'),'Evaluation:ModelLoaded', ...
    'Use a fresh MATLAB session with FAFA_Simulation closed.');
assert(opt.maxSteps<=3000,'Evaluation:Steps','This comparison supports at most 3000 steps.');
assert(all(opt.seeds<=2^32-1),'Evaluation:Seed','Seeds must fit uint32.');
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
assert(all(opt.stages<=numel(plan.stages)),'Evaluation:Stage','Unknown stage.');
% Detect drift: the evaluation fixed path must match the training path exactly.
engine=fileread(fullfile(runtime,'training_engine.m'));
marker='function [waypoints, velocity] = createFixedPath()';
offset=strfind(engine,marker);
fixed=fileread(fullfile(root,'+checkpointreview','fixed_path.m'));
assert(numel(offset)==1 && strcmp(strrep(strtrim(engine(offset:end)),char(13),''), ...
    strrep(strrep(strtrim(fixed),'fixed_path()','createFixedPath()'),char(13),'')), ...
    'Evaluation:PathDrift','Fixed-path implementation changed; update evaluator before comparison.');
paths=strings(0); episodes=[];
for ep=unique(opt.episodes,'stable')
    f=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep));
    assert(isfile(f),'Evaluation:Missing','Missing checkpoint: %s',f);
    checkpoint_select_agent(f);
    [~,actual]=checkpoint_resume_state(f);
    assert(actual==ep,'Evaluation:Episode','Checkpoint history does not match requested episode.');
    paths(end+1)=f; episodes(end+1)=actual; %#ok<AGROW>
end
if opt.includeLatest
    files=dir(fullfile(sessionDir,'checkpoints','Agent*.mat'));
    latestPaths=strings(0); latestNumbers=[];
    for i=1:numel(files)
        token=regexp(files(i).name,'^Agent_?(\d+)\.mat$','tokens','once');
        if isempty(token), continue; end
        latestPaths(end+1)=fullfile(files(i).folder,files(i).name); %#ok<AGROW>
        latestNumbers(end+1)=str2double(token{1}); %#ok<AGROW>
    end
    [~,order]=sort(latestNumbers,'descend'); latestPaths=latestPaths(order);
    % Only the highest numbered candidate and final/success are needed. Fail
    % explicitly if any is corrupt instead of silently calling an older one latest.
    if ~isempty(latestPaths), latestPaths=latestPaths(1); end
    for name=["Agent_Final.mat","Agent_Success.mat"]
        f=fullfile(sessionDir,name); if isfile(f), latestPaths(end+1)=f; end %#ok<AGROW>
    end
    assert(~isempty(latestPaths),'Evaluation:Missing','No latest checkpoint found.');
    progress=zeros(size(latestPaths));
    for i=1:numel(latestPaths)
        checkpoint_select_agent(latestPaths(i));
        [~,progress(i)]=checkpoint_resume_state(latestPaths(i));
    end
    [ep,i]=max(progress);
    if ~any(episodes==ep), paths(end+1)=latestPaths(i); episodes(end+1)=ep; end
end
assert(~isempty(paths),'Evaluation:Missing','Select at least one checkpoint.');
% Prepare every scenario before starting simulations; never call prepare(),
% which performs curriculum transitions and writes curriculum_state.json.
scenarios=cell(size(opt.stages));
global TARGET_SPEED DT WAYPOINT_SPACING
oldGlobals={TARGET_SPEED,DT,WAYPOINT_SPACING};
globalGuard=onCleanup(@() restoreGlobals(oldGlobals)); %#ok<NASGU>
TARGET_SPEED=15; DT=0.1; WAYPOINT_SPACING=1.5;
for i=1:numel(opt.stages)
    stage=plan.stages{opt.stages(i)};
    assert(all(stage.wind.east_mps==0) && all(stage.wind.north_mps==0) && ...
        all(stage.wind.turbulence==0),'Evaluation:Wind','This first comparison supports calm stages only.');
    switch stage.trajectory.type
        case 'mat'
            data=trainingcurriculum.load_trajectory(stage.trajectory,char(sessionDir));
        case 'fixed_builtin'
            [data.waypoints,data.velocity]=checkpointreview.fixed_path();
        otherwise
            error('Evaluation:Trajectory','Only fixed MAT and fixed_builtin stages are supported.');
    end
    data.id=stage.id; scenarios{i}=data;
end
[~,tag]=fileparts(tempname); tag=tag(1:10);
reports=fullfile(sessionDir,'reports'); if ~isfolder(reports), mkdir(reports); end
out=fullfile(reports,"evaluation_"+string(datetime('now','Format','yyyyMMdd_HHmmss'))+"_"+tag); mkdir(out);
report=struct('schema_version',1,'status','running','session_id',char(extractAfter(sessionDir, ...
    strlength(fileparts(sessionDir))+1)),'outputDir',char(out), ...
    'matlab_release',version('-release'),'device','cpu','use_exploration',false, ...
    'max_steps',opt.maxSteps,'seeds',opt.seeds,'stages',opt.stages, ...
    'scope','Fixed calm tasks at model initial state; not a held-out generalization test.', ...
    'termination_detail','IsDone only; physical termination cause is not instrumented.', ...
    'checkpoints',{{}},'results',{{}});
for i=1:numel(paths)
    report.checkpoints{i}=struct('file',char(paths(i)),'episode',episodes(i), ...
        'sha256',checkpointreview.sha256(paths(i)));
end
report.runtime_sha256=checkpointreview.sha256(fullfile(runtime,'training_engine.m'));
report.model_sha256=checkpointreview.sha256(fullfile(runtime,'FAFA_Simulation.slx'));
report.curriculum_sha256=checkpointreview.sha256(fullfile(sessionDir,'curriculum.json'));
save(fullfile(out,'scenarios.mat'),'scenarios','opt');
writeReport(fullfile(out,'evaluation.json'),report);
fprintf('Evaluation only: %d checkpoints x %d stages x %d seeds. Output: %s\n', ...
    numel(paths),numel(scenarios),numel(opt.seeds),out);
% Keep caches and all outputs away from training artifacts.
fileConfig=Simulink.fileGenControl('getConfig');
fileGuard=onCleanup(@() Simulink.fileGenControl('setConfig','config',fileConfig)); %#ok<NASGU>
cacheRoot=fullfile(tempdir,['ce_' tag]);
Simulink.fileGenControl('set','CacheFolder',fullfile(cacheRoot,'cache'), ...
    'CodeGenFolder',fullfile(cacheRoot,'codegen'),'createDir',true);
report.cache_directory=cacheRoot;
hadAgent=evalin('base',"exist('Agent_Stage2','var')==1"); oldAgent=[];
if hadAgent, oldAgent=evalin('base','Agent_Stage2'); end
agentGuard=onCleanup(@() restoreAgent(hadAgent,oldAgent)); %#ok<NASGU>
cd(runtime);
try
    report.phase='load_model';
    load_system(fullfile(runtime,'FAFA_Simulation.slx'));
    modelGuard=onCleanup(@() close_system('FAFA_Simulation',0)); %#ok<NASGU>
    report.phase='prepare_model';
    settingsGuard=checkpointreview.prepare_model('FAFA_Simulation',true,true); %#ok<NASGU>
    for c=1:numel(paths)
        for s=1:numel(scenarios)
            for seed=opt.seeds
                report.phase='load_checkpoint';
                report.current=struct('episode',episodes(c),'stage_id',scenarios{s}.id,'seed',seed);
                variables=whos('-file',paths(c)); agentName='saved_agent';
                if ~any(strcmp({variables.name},agentName)), agentName='Agent_Stage2'; end
                data=load(paths(c),agentName); agent=data.(agentName);
                clear data
                actor=getActor(agent); actor.UseDevice='cpu'; agent=setActor(agent,actor);
                critic=getCritic(agent); critic.UseDevice='cpu'; agent=setCritic(agent,critic);
                agent.UseExplorationPolicy=false;
                beforeActor=getLearnableParameters(getActor(agent));
                beforeCritic=getLearnableParameters(getCritic(agent));
                assignin('base','Agent_Stage2',agent);
                env=rlSimulinkEnv('FAFA_Simulation','FAFA_Simulation/RL Agent', ...
                    getObservationInfo(agent),getActionInfo(agent),'UseFastRestart','off');
                env.ResetFcn=@(in) resetScenario(in,scenarios{s});
                rng(seed,'twister');
                fprintf('Evaluating episode %d / %s / seed %d ...\n',episodes(c),scenarios{s}.id,seed);
                report.phase='simulate';
                experience=sim(env,agent,rlSimulationOptions('MaxSteps',opt.maxSteps, ...
                    'NumSimulations',1,'UseParallel',false,'StopOnError','on'));
                assert(isequaln(beforeActor,getLearnableParameters(getActor(agent))) && ...
                    isequaln(beforeCritic,getLearnableParameters(getCritic(agent))), ...
                    'Evaluation:Weights','Unexpected weight mutation during evaluation.');
                row=checkpointreview.summarize(experience,opt.maxSteps);
                row.checkpoint_episode=episodes(c); row.stage_id=scenarios{s}.id; row.seed=seed;
                trace=sprintf('ep%d_stage%d_seed%d.mat',episodes(c),opt.stages(s),seed);
                save(fullfile(out,trace),'experience','-v7.3'); row.trace=trace;
                report.results{end+1}=row;
                report.phase='save_result';
                writeReport(fullfile(out,'evaluation.json'),report);
                fprintf('Reward %.2f | steps %d | %s\n',row.reward,row.steps,row.end_signal);
            end
        end
    end
    report.phase='verify_sources';
    for i=1:numel(paths)
        assert(strcmp(report.checkpoints{i}.sha256,checkpointreview.sha256(paths(i))), ...
            'Evaluation:SourceChanged','Source checkpoint changed during evaluation.');
    end
    report.status='complete'; report.weights_unchanged=true;
catch err
    failEvaluation(err,fullfile(out,'evaluation.json'),report,writeReport);
end
report.phase='complete';
writeReport(fullfile(out,'evaluation.json'),report);
disp(struct2table([report.results{:}]));
fprintf('Complete. No training or rollback. Share: %s\n',fullfile(out,'evaluation.json'));
end

function in=resetScenario(in,data)
for name=["wind_E0","wind_N0","wind_turbulance_value0"]
    in=setVariable(in,name,0,'Workspace','FAFA_Simulation');
end
in=setVariable(in,'waypoints',data.waypoints,'Workspace','FAFA_Simulation');
in=setVariable(in,'velocity',data.velocity,'Workspace','FAFA_Simulation');
end
function restoreCaller(p,f,r)
cd(f); path(p); rng(r);
end
function restoreGlobals(values)
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=values{1}; DT=values{2}; WAYPOINT_SPACING=values{3};
end
function restoreAgent(hadAgent,oldAgent)
if hadAgent, assignin('base','Agent_Stage2',oldAgent); else, evalin('base','clear Agent_Stage2'); end
end
