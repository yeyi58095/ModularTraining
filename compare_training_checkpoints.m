function report = compare_training_checkpoints(sessionDir,opt)
% 獨立 checkpoint 評估：鎖住停止的課程 run，配對指定階段／seed，逐次以 CPU 純 sim 比較。
% 回傳 report 並保存情境、trace 與 JSON；只修改記憶體 agent／暫存模型，不續訓、不換階段、不回滾。
% Read-only, serial CPU evaluation of stopped curriculum checkpoints.
% No train(), checkpoint replacement, curriculum transition or automatic resume.
arguments
    sessionDir (1,1) string
    opt.episodes (1,:) double {mustBeInteger,mustBePositive} = [6100 10600]
    opt.includeLatest (1,1) logical = true
    opt.stages (1,:) double {mustBeInteger,mustBePositive} = [1 2 3]
    opt.seeds (1,:) double {mustBeInteger,mustBeNonnegative} = 101
    opt.maxSteps (1,1) double {mustBeInteger,mustBePositive} = 3000
    opt.diagnostics (1,1) logical = false
    opt.guidanceVariant (1,1) string {mustBeMember(opt.guidanceVariant,["baseline","endpoint_lookahead","endpoint_lookahead_v2","valid_history","progress_window"])} = "baseline"
end
root=fileparts(mfilename('fullpath')); runtime=fullfile(root,'runtime');
oldPath=path; oldFolder=pwd; oldRng=rng;
restore=onCleanup(@() restoreCaller(oldPath,oldFolder,oldRng)); %#ok<NASGU>
addpath(root,runtime);
if ~java.io.File(char(sessionDir)).isAbsolute(), sessionDir=fullfile(root,sessionDir); end
sessionDir=string(char(java.io.File(char(sessionDir)).getCanonicalPath()));
% 取得停止 run 的排他鎖；評估期間不允許 supervisor 同時續訓。
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
assert(~isempty(opt.seeds) && numel(unique(opt.seeds))==numel(opt.seeds), ...
    'Evaluation:Seed','Provide nonempty unique seeds.');
assert(~isempty(opt.stages) && numel(unique(opt.stages))==numel(opt.stages), ...
    'Evaluation:Stage','Provide nonempty unique stages.');
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
assert(all(opt.stages<=numel(plan.stages)),'Evaluation:Stage','Unknown stage.');
% Detect drift: the evaluation fixed path must match the training path exactly.
% 固定路徑評估函式與訓練端逐字比對；連註解也需同步，避免環境漂移。
engine=fileread(fullfile(runtime,'training_engine.m'));
marker='function [waypoints, velocity] = createFixedPath()';
offset=strfind(engine,marker);
fixed=fileread(fullfile(root,'+checkpointreview','fixed_path.m'));
assert(numel(offset)==1 && strcmp(strrep(strtrim(engine(offset:end)),char(13),''), ...
    strrep(strrep(strtrim(fixed),'fixed_path()','createFixedPath()'),char(13),'')), ...
    'Evaluation:PathDrift','Fixed-path implementation changed; update evaluator before comparison.');
% 候選回合由 checkpoint 內歷史核對，latest 也必須是真實可讀進度。
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
% One saved scenario per stage/seed; path draws are independent of wind draws.
randomSource=fileread(fullfile(root,'+checkpointreview','random_path.m'));
a=strfind(engine,'function [waypoints, velocity] = createPath_Stage2()');
b=strfind(engine,'% Display path');
assert(numel(a)==1 && numel(b)==1 && strcmp( ...
    strrep(strtrim(engine(a:b-1)),char(13),''), ...
    strrep(strrep(strtrim(randomSource),'random_path()','createPath_Stage2()'),char(13),'')), ...
    'Evaluation:PathDrift','Random-path implementation changed; update evaluator.');
scenarios=cell(numel(opt.stages),numel(opt.seeds));
global TARGET_SPEED DT WAYPOINT_SPACING
oldGlobals={TARGET_SPEED,DT,WAYPOINT_SPACING};
globalGuard=onCleanup(@() restoreGlobals(oldGlobals)); %#ok<NASGU>
TARGET_SPEED=15; DT=0.1; WAYPOINT_SPACING=1.5;
for i=1:numel(opt.stages)
    for j=1:numel(opt.seeds)
        scenarios{i,j}=checkpointreview.scenario(plan.stages{opt.stages(i)}, ...
            char(sessionDir),opt.seeds(j));
    end
end
[~,tag]=fileparts(tempname); tag=tag(1:10);
reports=fullfile(sessionDir,'reports'); if ~isfolder(reports), mkdir(reports); end
out=fullfile(reports,"evaluation_"+string(datetime('now','Format','yyyyMMdd_HHmmss'))+"_"+tag); mkdir(out);
report=struct('schema_version',2,'status','running','session_id',char(extractAfter(sessionDir, ...
    strlength(fileparts(sessionDir))+1)),'outputDir',char(out), ...
    'matlab_release',version('-release'),'device','cpu','use_exploration',false, ...
    'max_steps',opt.maxSteps,'seeds',opt.seeds,'stages',opt.stages, ...
    'scope','Paired seeded paths and sampled integer winds at model initial state; diagnostic scenarios, not certified generalization.', ...
    'termination_detail','Terminal observation threshold evidence only; not instrumented IsDone branch attribution.', ...
    'checkpoints',{{}},'results',{{}});
for i=1:numel(paths)
    report.checkpoints{i}=struct('file',char(paths(i)),'episode',episodes(i), ...
        'sha256',checkpointreview.sha256(paths(i)));
end
report.runtime_sha256=checkpointreview.sha256(fullfile(runtime,'training_engine.m'));
report.model_sha256=checkpointreview.sha256(fullfile(runtime,'FAFA_Simulation.slx'));
report.curriculum_sha256=checkpointreview.sha256(fullfile(sessionDir,'curriculum.json'));
report.random_path_sha256=checkpointreview.sha256(fullfile(root,'+checkpointreview','random_path.m'));
report.turbulence_seed_policy='Internal noise seeds remain as stored in the model; MATLAB scenario seed does not independently seed every Simulink noise source.';
save(fullfile(out,'scenarios.mat'),'scenarios','opt');
writeReport(fullfile(out,'evaluation.json'),report);
fprintf('Evaluation only: %d checkpoints x %d stages x %d seeds. Output: %s\n', ...
    numel(paths),numel(opt.stages),numel(opt.seeds),out);
% Keep caches and all outputs away from training artifacts.
fileConfig=Simulink.fileGenControl('getConfig');
fileGuard=onCleanup(@() Simulink.fileGenControl('setConfig','config',fileConfig)); %#ok<NASGU>
cacheRoot=fullfile(tempdir,['ce_' tag]);
Simulink.fileGenControl('set','CacheFolder',fullfile(cacheRoot,'cache'), ...
    'CodeGenFolder',fullfile(cacheRoot,'codegen'),'createDir',true);
report.cache_directory=cacheRoot;
report.diagnostics_enabled=opt.diagnostics;
report.guidance_variant=char(opt.guidanceVariant);
hadAgent=evalin('base',"exist('Agent_Stage2','var')==1"); oldAgent=[];
if hadAgent, oldAgent=evalin('base','Agent_Stage2'); end
agentGuard=onCleanup(@() restoreAgent(hadAgent,oldAgent)); %#ok<NASGU>
cd(runtime);
% Reassert package visibility after cache configuration and folder changes.
addpath(root,runtime,'-begin');
% 模擬與報告可能失敗；入口捕捉並保留原始 phase／堆疊，不讓寫報告例外遮蓋原錯誤。
try
    report.phase='load_model';
    modelFile=fullfile(runtime,'FAFA_Simulation.slx');
    if opt.diagnostics || opt.guidanceVariant~="baseline"
        modelFolder=fullfile(cacheRoot,'model'); mkdir(modelFolder);
        copyfile(modelFile,fullfile(modelFolder,'FAFA_Simulation.slx'));
        modelFile=fullfile(modelFolder,'FAFA_Simulation.slx');
        cd(modelFolder);
    end
    load_system(modelFile);
    modelGuard=onCleanup(@() close_system('FAFA_Simulation',0)); %#ok<NASGU>
    addpath(root,runtime,'-begin');
    if opt.guidanceVariant~="baseline"
        chart=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function12');
        assert(isscalar(chart),'Evaluation:GuidanceDrift','Expected one guidance chart.');
        if any(opt.guidanceVariant==["valid_history","progress_window"])
            chart.Script=checkpointreview.history_candidate(chart.Script);
        else
            chart.Script=checkpointreview.endpoint_candidate(chart.Script,opt.guidanceVariant=="endpoint_lookahead_v2");
        end
        scriptFile=fullfile(out,'candidate_guidance.m');
        fid=fopen(scriptFile,'w','n','UTF-8');
        assert(fid~=-1,'Evaluation:ReportWrite','Cannot save candidate source.');
        fileGuardScript=onCleanup(@() fclose(fid));
        fprintf(fid,'%s',chart.Script); clear fileGuardScript;
        report.candidate_script_sha256=checkpointreview.sha256(scriptFile);
        if opt.guidanceVariant=="progress_window"
            windowChart=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function3');
            assert(isscalar(windowChart),'Evaluation:WindowDrift','Expected one window chart.');
            windowChart.Script=checkpointreview.progress_window_candidate(windowChart.Script);
            windowFile=fullfile(out,'candidate_window.m');
            fid=fopen(windowFile,'w','n','UTF-8');
            assert(fid~=-1,'Evaluation:ReportWrite','Cannot save window source.');
            windowGuard=onCleanup(@() fclose(fid));
            fprintf(fid,'%s',windowChart.Script); clear windowGuard;
            report.candidate_window_sha256=checkpointreview.sha256(windowFile);
        end
    end
    report.phase='prepare_model';
    settingsGuard=checkpointreview.prepare_model('FAFA_Simulation',true,true); %#ok<NASGU>
    if opt.diagnostics
        report.diagnostic_signals=checkpointreview.instrument_model('FAFA_Simulation');
    end
    for c=1:numel(paths)
        for s=1:numel(opt.stages)
            for j=1:numel(opt.seeds)
                seed=opt.seeds(j); scenario=scenarios{s,j};
                report.phase='load_checkpoint';
                report.current=struct('episode',episodes(c),'stage_id',scenario.id,'seed',seed);
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
                env.ResetFcn=@(in) resetScenario(in,scenario);
                rng(seed,'twister');
                fprintf('Evaluating episode %d / %s / seed %d ...\n',episodes(c),scenario.id,seed);
                report.phase='simulate';
                experience=sim(env,agent,rlSimulationOptions('MaxSteps',opt.maxSteps, ...
                    'NumSimulations',1,'UseParallel',false,'StopOnError','on'));
                assert(isequaln(beforeActor,getLearnableParameters(getActor(agent))) && ...
                    isequaln(beforeCritic,getLearnableParameters(getCritic(agent))), ...
                    'Evaluation:Weights','Unexpected weight mutation during evaluation.');
                row=checkpointreview.summarize(experience,opt.maxSteps);
                row.wind_east_mps=scenario.wind(1); row.wind_north_mps=scenario.wind(2);
                row.turbulence=scenario.wind(3);
                row.checkpoint_episode=episodes(c); row.stage_id=scenario.id; row.seed=seed;
                trace=sprintf('ep%d_stage%d_seed%d.mat',episodes(c),opt.stages(s),seed);
                if opt.diagnostics
                    simulationOutput=experience.SimulationInfo(1);
                    diagnostics=simulationOutput.get('review_signals');
                    assert(isa(diagnostics,'Simulink.SimulationData.Dataset'), ...
                        'Evaluation:Logging','Diagnostic signals were not returned.');
                    for signal=string({report.diagnostic_signals.name})
                        logged=diagnostics.getElement(char(signal));
                        assert(~isempty(logged.Values),'Evaluation:Logging','Missing signal: %s',signal);
                    end
                    save(fullfile(out,trace),'experience','diagnostics','-v7.3');
                else
                    save(fullfile(out,trace),'experience','-v7.3');
                end
                row.trace=trace;
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
    assert(strcmp(report.model_sha256,checkpointreview.sha256(fullfile(runtime,'FAFA_Simulation.slx'))), ...
        'Evaluation:SourceChanged','Original runtime model changed during evaluation.');
catch err
    % Keep this inline: even a pre-bound package handle can fail to resolve
    % after a model callback or cache configuration changes MATLAB's path.
    fprintf(2,'Evaluation failed during %s: %s\n',report.phase,err.message);
    try
        report.status='failed';
        report.error=struct('identifier',err.identifier,'message',err.message, ...
            'report',getReport(err,'extended','hyperlinks','off'));
        report.error.cwd=pwd;
        report.error.project_on_path=any(strcmp(strsplit(path,pathsep),root));
        writeReport(fullfile(out,'evaluation.json'),report);
    catch writeError
        fprintf(2,'Could not save evaluation diagnostics: %s\n',writeError.message);
    end
    rethrow(err);
end
report.summary=checkpointreview.aggregate(report.results);
report.phase='complete';
writeReport(fullfile(out,'evaluation.json'),report);
disp(struct2table([report.results{:}]));
fprintf('Complete. No training or rollback. Share: %s\n',fullfile(out,'evaluation.json'));
end

function in=resetScenario(in,data)
% 將已保存情境的路徑、速度與風場送入這次模擬，不重新抽樣情境。
names=["wind_E0","wind_N0","wind_turbulance_value0"];
for k=1:3
    in=setVariable(in,names(k),data.wind(k),'Workspace','FAFA_Simulation');
end
in=setVariable(in,'waypoints',data.waypoints,'Workspace','FAFA_Simulation');
in=setVariable(in,'velocity',data.velocity,'Workspace','FAFA_Simulation');
end
function restoreCaller(p,f,r)
% 恢復評估前的 MATLAB 路徑、工作目錄與 RNG，避免工具影響呼叫者。
cd(f); path(p); rng(r);
end
function restoreGlobals(values)
% 將評估暫時使用的全域軌跡參數恢復成呼叫前值。
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=values{1}; DT=values{2}; WAYPOINT_SPACING=values{3};
end
function restoreAgent(hadAgent,oldAgent)
% 恢復 base workspace 原 agent；原先不存在則清除本次暫存變數。
if hadAgent, assignin('base','Agent_Stage2',oldAgent); else, evalin('base','clear Agent_Stage2'); end
end

function writeReport(file,value)
% 入口同檔的 JSON writer，讓 root package 路徑失效時仍可保存原始錯誤報告。
% Local function stays callable when project packages leave the search path.
temporary=[tempname(fileparts(file)) '.json'];
fid=fopen(temporary,'w','n','UTF-8');
assert(fid~=-1,'Evaluation:ReportWrite','Cannot write %s',temporary);
guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
clear guard;
[ok,message]=movefile(temporary,file,'f');
assert(ok,'Evaluation:ReportWrite','%s',message);
end
