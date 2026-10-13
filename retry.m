function info = retry(varargin)
% 訓練入口：建立新實驗或沿用指定 run 的模型、課程及控制設定。
% 輸入為名稱參數；回傳 info（run、診斷目錄與 supervisor）。start=false 仍寫入準備檔，但不啟動程序。
% RETRY(model="ppo_lstm128", workers=6) starts an isolated experiment.
% RETRY(resume="absolute session folder") resumes its saved model specification.
% start=false prepares a reviewable session without launching MATLAB processes.
% 入口參數：workers 是要求上限，minWorkers 是最低可接受數；checkpointEvery 是保存頻率。
p = inputParser;
p.addParameter('model',""); p.addParameter('resume',"");
p.addParameter('curriculum',"");
p.addParameter('workers',6); p.addParameter('fallbackWorkers',[4 2]);
p.addParameter('minWorkers',1);
% episodesPerProcess 是每個 MATLAB 程序新增的段落回合數；課程還會受階段／guard 剩餘預算限制。
p.addParameter('checkpointEvery',100); p.addParameter('episodesPerProcess',1000);
% targetReward／averageWindow 用於非課程成功規則；課程以 JSON advance_when 為準。
p.addParameter('targetReward',2900); p.addParameter('averageWindow',50);
p.addParameter('device',"gpu"); p.addParameter('maxAttempts',0);
% watchdog 管啟動／日誌逾時；無進度失敗上限防止重複失敗，0 表示不限制該項。
p.addParameter('maxNoProgressFailures',3); p.addParameter('retryDelaySeconds',30);
p.addParameter('startupTimeoutSeconds',600); p.addParameter('stallTimeoutSeconds',1800);
p.addParameter('licenseRetryDelaySeconds',60); p.addParameter('start',true);
% varargin{:} 將 cell 參數展開；p.Results 是解析值，p.UsingDefaults 用於辨別哪些參數本次未指定。
p.parse(varargin{:}); opt = p.Results;
root = fileparts(mfilename('fullpath'));
runtime = fullfile(root,'runtime');
required = {'checkpoint_supervisor.ps1','checkpoint_watchdog.ps1', ...
    'checkpoint_worker_diagnostics.ps1','checkpoint_attempt.m','checkpoint_open_pool.m', ...
    'training_engine.m','checkpoint_run_log_dir.m','FAFA_Simulation.slx'};
% fullfile 依平台拼路徑，assert 在缺少依賴時立即中止，不等到訓練才發現。
for k=1:numel(required)
    assert(isfile(fullfile(runtime,required{k})),'Modular:MissingDependency', ...
        'Missing isolated runtime file: %s',required{k});
end
% Temporary path changes only affect this function; child processes use runtime paths.
% onCleanup 在函式返回或拋錯時還原 MATLAB path；只對這個呼叫暫時加路徑。
oldPath = path; pathGuard = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,'-begin');
isResume = strlength(string(opt.resume)) > 0;
plan=[];
if strlength(string(opt.curriculum))>0
    assert(~isResume,'Curriculum:Immutable','Resume uses the saved curriculum; do not supply a new plan.');
    planFile=resolve_curriculum_path(opt.curriculum);
    plan=trainingcurriculum.load_plan(planFile,true);
    assert(strlength(string(opt.model))==0 || strcmp(opt.model,plan.model), ...
        'Curriculum:Model','model must match the curriculum model.');
    opt.model=plan.model;
end
% 續訓讀既有快照；新建才從共享 profile／課程建立隔離 run。
if isResume
    folder = projectPath(root,opt.resume);
    assert(~endsWith(folder,'.preparing'),'Recovery:Incomplete','Recovery preparation is incomplete.');
    assert(isfile(fullfile(folder,'model.json')) && isfile(fullfile(folder,'control.json')), ...
        'Modular:ResumeFolder','Resume requires a ModularTraining session folder with model.json and control.json.');
    spec = jsondecode(fileread(fullfile(folder,'model.json')));
    cfg = jsondecode(fileread(fullfile(folder,'control.json')));
    if isfile(fullfile(folder,'curriculum.json')), cfg.curriculumEnabled=true; end
    if isfield(cfg,'curriculumEnabled') && cfg.curriculumEnabled
        savedPlan=trainingcurriculum.load_plan(fullfile(folder,'curriculum.json'),true);
        assert(strcmp(savedPlan.model,spec.name),'Curriculum:Model','Saved plan/model mismatch.');
    end
    if strlength(string(opt.model)) > 0
        assert(strcmp(opt.model,spec.name),'Modular:ModelMismatch', ...
            'Resume uses model %s. Use a new experiment to change architecture.',spec.name);
    end
    assert(isfolder(fullfile(folder,'model_source','+trainingmodels')), ...
        'Modular:MissingSnapshot','Saved model source is missing.');
else
    name = string(opt.model);
    if strlength(name)==0, name="ppo_lstm128"; end
    assert(isscalar(name) && ~isempty(regexp(name,'^[a-z][a-z0-9_]*$','once')), ...
        'Modular:ModelName','Use a model profile name, not a file path.');
    spec = trainingmodels.load_profile(name);
    assert(strcmp(spec.name,name) && strcmp(spec.algorithm,'PPO'), ...
        'Modular:Profile','Profile name must match its filename; this runtime currently supports PPO.');
    cfg = struct('curriculumEnabled',~isempty(plan));
    if ~isempty(plan)
        [~,planName]=fileparts(planFile);
        [planParent,planFolder]=fileparts(fileparts(planFile));
        if strcmpi(planName,'curriculum') && strcmpi(planParent,fullfile(root,'experiments'))
            planName=planFolder;
        end
        sessions=fullfile(root,'experiments',planName,'runs');
        cfg.curriculumName=planName;
    else
        sessions=fullfile(root,'+trainingmodels',name,'runs');
    end
    if ~isfolder(sessions), mkdir(sessions); end
    [~,tag]=fileparts(tempname(sessions));
    % Keep experiment IDs short for Windows MAT/HDF5 path limits.
    folder=fullfile(sessions,[char(datetime('now','Format','yyyyMMdd_HHmmss')) '_' tag]);
end
% 只覆蓋本次明確傳入的 resume 參數，未指定者沿用既有 control。
keys = {'workers','minWorkers','fallbackWorkers','checkpointEvery','episodesPerProcess','targetReward', ...
    'averageWindow','device','maxAttempts','maxNoProgressFailures','retryDelaySeconds', ...
    'startupTimeoutSeconds','stallTimeoutSeconds','licenseRetryDelaySeconds'};
for k=1:numel(keys)
    key=keys{k}; dest=key;
    if strcmp(key,'workers'), dest='numWorkers'; end
    if strcmp(key,'device'), dest='trainingDevice'; end
    if ~isResume || ~ismember(key,p.UsingDefaults), cfg.(dest)=opt.(key); end
end
if ~isfield(cfg,'minWorkers'), cfg.minWorkers=1; end % Legacy control.json.
for key={'numWorkers','minWorkers','checkpointEvery','episodesPerProcess','averageWindow'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','integer','positive','finite'});
end
validateattributes(cfg.fallbackWorkers,{'numeric'},{'integer','positive','finite'});
assert(cfg.minWorkers<=cfg.numWorkers,'Modular:WorkerRange','minWorkers must not exceed workers.');
for key={'maxAttempts','maxNoProgressFailures'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','integer','nonnegative','finite'});
end
for key={'retryDelaySeconds','startupTimeoutSeconds','stallTimeoutSeconds','licenseRetryDelaySeconds'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','nonnegative','finite'});
end
validateattributes(cfg.targetReward,{'numeric'},{'scalar','finite'});
if isfield(cfg,'curriculumEnabled') && cfg.curriculumEnabled
    assert(ismember('targetReward',p.UsingDefaults),'Curriculum:Criteria', ...
        'Curriculum completion uses advance_when in the saved JSON, not targetReward.');
end
assert(any(strcmp(cfg.trainingDevice,{'cpu','gpu'})),'Modular:Device','device must be cpu or gpu.');
assert(cfg.episodesPerProcess>=max(cfg.checkpointEvery,cfg.averageWindow), ...
    'Modular:Segment','episodesPerProcess must cover checkpointEvery and averageWindow.');
assert(~isfile(fullfile(folder,'Agent_Success.mat')),'Modular:Completed','Experiment already succeeded.');
if ~isfolder(folder), mkdir(folder); end
% 寫設定前取得 run 排他鎖，與 supervisor／診斷工具互斥。
lock=System.IO.File.Open(fullfile(folder,'supervisor.lock'), ...
    System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose());
if ~isResume
    writeJson(fullfile(folder,'model.json'),spec);
    if ~isempty(plan), trainingcurriculum.snapshot(plan,planFile,folder); end
    snapshot=fullfile(folder,'model_source'); mkdir(snapshot);
    % Copy source only: model folders now also contain potentially large runs.
    source = fullfile(root,'+trainingmodels');
    destination = fullfile(snapshot,'+trainingmodels'); mkdir(destination);
    copyfile(fullfile(source,'*.m'),destination);
    models = dir(source);
    for k=1:numel(models)
        entry = models(k);
        if ~entry.isdir || startsWith(entry.name,'.'), continue; end
        modelSource = fullfile(source,entry.name);
        if ~isfile(fullfile(modelSource,[entry.name '.m'])), continue; end
        modelDestination = fullfile(destination,entry.name); mkdir(modelDestination);
        copyfile(fullfile(modelSource,'*.m'),modelDestination);
    end
else
    [~,tag]=fileparts(tempname(folder));
    history=fullfile(folder,'control_history'); if ~isfolder(history), mkdir(history); end
    copyfile(fullfile(folder,'control.json'),fullfile(history,[tag '.json']));
end
% control 使用本專案與此 run 的絕對位置，不依賴 Flower 路徑。
cfg.scriptDir=runtime; cfg.sessionDir=folder; cfg.modularRoot=root;
if ~isResume
    cfg.diagnosticDir=fullfile(folder,'diagnostics');
elseif ~isfield(cfg,'diagnosticDir')
    % Existing sessions retain their original diagnostic location on resume.
    if ~isfield(cfg,'diagnosticRoot'), cfg.diagnosticRoot=fullfile(root,'training_diagnostics'); end
    cfg.diagnosticDir=fullfile(cfg.diagnosticRoot,char(java.io.File(folder).getName()));
end
cfg.matlabExe=fullfile(matlabroot,'bin','matlab.exe');
cfg.resumeAgentFile=''; % Supervisor searches only this session for newest valid checkpoints.
writeJson(fullfile(folder,'control.json'),cfg);
stopFile=fullfile(folder,'STOP');
if opt.start && isfile(stopFile), delete(stopFile); end
clear lockGuard;
info=struct('sessionDir',folder,'model',spec.name,'supervisor',[], ...
    'diagnosticDir',cfg.diagnosticDir);
% 只有真正啟動時建立隱藏 supervisor；start=false 返回準備資訊。
if opt.start
    processInfo=System.Diagnostics.ProcessStartInfo;
    processInfo.FileName='powershell.exe';
    processInfo.Arguments=sprintf('-NoProfile -ExecutionPolicy Bypass -File "%s" -ConfigFile "%s"', ...
        fullfile(runtime,'checkpoint_supervisor.ps1'),fullfile(folder,'control.json'));
    processInfo.UseShellExecute=false; processInfo.CreateNoWindow=true;
    processInfo.WorkingDirectory=runtime;
    info.supervisor=System.Diagnostics.Process.Start(processInfo);
    fprintf('Supervisor PID: %d\n',info.supervisor.Id);
end
fprintf('Model: %s\nSession: %s\nDiagnostics: %s\n',spec.name,folder,info.diagnosticDir);
fprintf('To stop: create an empty STOP file in this session folder.\n');
end

function resolved = projectPath(root,value)
% 相對路徑先接到專案 root 再 canonicalize，避免 Java 工作目錄差異。
% Java's process working directory can differ from MATLAB's Current Folder.
% Anchor relative inputs before canonicalizing; preserve absolute inputs.
value=char(value);
if ~java.io.File(value).isAbsolute()
    value=fullfile(root,value);
end
resolved=char(java.io.File(value).getCanonicalPath());
end

function writeJson(file,value)
% 以 UTF-8 保存 JSON；輸入為檔名／資料，呼叫端決定寫入位置與時機。
fid=fopen(file,'w','n','UTF-8'); assert(fid~=-1,'Cannot write %s',file);
guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
end
