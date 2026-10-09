function info = retry(varargin)
% RETRY(model="ppo_lstm128", workers=6) starts an isolated experiment.
% RETRY(resume="absolute session folder") resumes its saved model specification.
% start=false prepares a reviewable session without launching MATLAB processes.
p = inputParser;
p.addParameter('model',""); p.addParameter('resume',"");
p.addParameter('workers',6); p.addParameter('fallbackWorkers',[4 2]);
p.addParameter('checkpointEvery',100); p.addParameter('episodesPerProcess',1000);
p.addParameter('targetReward',2900); p.addParameter('averageWindow',50);
p.addParameter('device',"gpu"); p.addParameter('maxAttempts',0);
p.addParameter('maxNoProgressFailures',3); p.addParameter('retryDelaySeconds',30);
p.addParameter('startupTimeoutSeconds',600); p.addParameter('stallTimeoutSeconds',1800);
p.addParameter('licenseRetryDelaySeconds',60); p.addParameter('start',true);
p.parse(varargin{:}); opt = p.Results;
root = fileparts(mfilename('fullpath'));
runtime = fullfile(root,'runtime');
required = {'checkpoint_supervisor.ps1','checkpoint_watchdog.ps1', ...
    'checkpoint_worker_diagnostics.ps1','checkpoint_attempt.m','checkpoint_open_pool.m', ...
    'training_engine.m','checkpoint_run_log_dir.m','FAFA_Simulation.slx'};
for k=1:numel(required)
    assert(isfile(fullfile(runtime,required{k})),'Modular:MissingDependency', ...
        'Missing isolated runtime file: %s',required{k});
end
% Temporary path changes only affect this function; child processes use runtime paths.
oldPath = path; pathGuard = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(root,'-begin');
isResume = strlength(string(opt.resume)) > 0;
if isResume
    folder = char(java.io.File(char(opt.resume)).getCanonicalPath());
    assert(isfile(fullfile(folder,'model.json')) && isfile(fullfile(folder,'control.json')), ...
        'Modular:ResumeFolder','Resume requires a ModularTraining session folder with model.json and control.json.');
    spec = jsondecode(fileread(fullfile(folder,'model.json')));
    cfg = jsondecode(fileread(fullfile(folder,'control.json')));
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
    cfg = struct();
    sessions = fullfile(root,'+trainingmodels',name,'runs');
    if ~isfolder(sessions), mkdir(sessions); end
    [~,tag]=fileparts(tempname(sessions));
    % Model name is already in the parent path; do not repeat it (Windows limits).
    folder=fullfile(sessions,[char(datetime('now','Format','yyyyMMdd_HHmmss')) '_' tag]);
end
keys = {'workers','fallbackWorkers','checkpointEvery','episodesPerProcess','targetReward', ...
    'averageWindow','device','maxAttempts','maxNoProgressFailures','retryDelaySeconds', ...
    'startupTimeoutSeconds','stallTimeoutSeconds','licenseRetryDelaySeconds'};
for k=1:numel(keys)
    key=keys{k}; dest=key;
    if strcmp(key,'workers'), dest='numWorkers'; end
    if strcmp(key,'device'), dest='trainingDevice'; end
    if ~isResume || ~ismember(key,p.UsingDefaults), cfg.(dest)=opt.(key); end
end
for key={'numWorkers','checkpointEvery','episodesPerProcess','averageWindow'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','integer','positive','finite'});
end
validateattributes(cfg.fallbackWorkers,{'numeric'},{'integer','positive','finite'});
for key={'maxAttempts','maxNoProgressFailures'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','integer','nonnegative','finite'});
end
for key={'retryDelaySeconds','startupTimeoutSeconds','stallTimeoutSeconds','licenseRetryDelaySeconds'}
    validateattributes(cfg.(key{1}),{'numeric'},{'scalar','nonnegative','finite'});
end
validateattributes(cfg.targetReward,{'numeric'},{'scalar','finite'});
assert(any(strcmp(cfg.trainingDevice,{'cpu','gpu'})),'Modular:Device','device must be cpu or gpu.');
assert(cfg.episodesPerProcess>=max(cfg.checkpointEvery,cfg.averageWindow), ...
    'Modular:Segment','episodesPerProcess must cover checkpointEvery and averageWindow.');
assert(~isfile(fullfile(folder,'Agent_Success.mat')),'Modular:Completed','Experiment already succeeded.');
if ~isfolder(folder), mkdir(folder); end
lock=System.IO.File.Open(fullfile(folder,'supervisor.lock'), ...
    System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose());
if ~isResume
    writeJson(fullfile(folder,'model.json'),spec);
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

function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8'); assert(fid~=-1,'Cannot write %s',file);
guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
end
