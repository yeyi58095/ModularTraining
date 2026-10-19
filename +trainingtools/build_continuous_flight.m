function manifest = build_continuous_flight()
% Build a separate simulation-only SLX; never modify the training environment.
root=fileparts(fileparts(mfilename('fullpath')));
old=path;restore=onCleanup(@()path(old)); %#ok<NASGU>
addpath(root,'-begin');
source=fullfile(root,'environments','spatial_v2','FAFA_Simulation.slx');
expected='997adbbd29b199c88e956d0778c1d8022547c60e46abd9943db1d325c295d557';
assert(strcmpi(checkpointreview.sha256(source),expected),'Continuous:Source','Unexpected spatial_v2 model.');
folder=fullfile(root,'simulations','continuous_flight');
target=fullfile(folder,'FAFA_ContinuousFlight.slx');
assert(~isfile(target),'Continuous:Exists','Refusing to overwrite existing continuous-flight model.');
mdl='FAFA_ContinuousFlight';
assert(~bdIsLoaded(mdl),'Continuous:Loaded','Close continuous-flight model before building.');
if ~isfolder(folder),mkdir(folder);end
copyfile(source,target);
load_system(target);
cleanup=onCleanup(@()close_system(mdl,0)); %#ok<NASGU>
agentPorts=get_param([mdl '/RL Agent'],'PortHandles');
donePorts=get_param([mdl '/isdone'],'PortHandles');
line=get_param(agentPorts.Inport(3),'Line');
assert(line~=-1 && get_param(line,'SrcPortHandle')==donePorts.Outport(1), ...
    'Continuous:Wiring','Unexpected source isDone wiring.');
delete_line(mdl,'isdone/1','RL Agent/3');
add_block('simulink/Sources/Constant',[mdl '/EpisodeDoneDisabled'], ...
    'Value','0','OutDataTypeStr','boolean','Position',[560 -155 610 -125]);
add_line(mdl,'EpisodeDoneDisabled/1','RL Agent/3','autorouting','on');
add_block('simulink/Sinks/To Workspace',[mdl '/IsDoneDiagnostic'], ...
    'VariableName','isDoneDiagnostic','SaveFormat','Timeseries', ...
    'Position',[560 -60 675 -30]);
add_line(mdl,'isdone/1','IsDoneDiagnostic/1','autorouting','on');
set_param(mdl,'StopTime','300');
save_system(mdl,target);
assert(strcmpi(checkpointreview.sha256(source),expected),'Continuous:SourceChanged','Training model changed.');
manifest=struct('schema_version',1,'purpose','continuous Simulink flight simulation only', ...
    'source','environments/spatial_v2/FAFA_Simulation.slx','source_sha256',expected, ...
    'model_file','FAFA_ContinuousFlight.slx','sha256',checkpointreview.sha256(target), ...
    'episode_termination_enabled',false,'original_done_logged_as','isDoneDiagnostic', ...
    'stop_time_seconds',300,'standard_evaluation',false,'hardware_deployment',false, ...
    'changes',{{'RL Agent done input replaced with boolean false', ...
    'Original isdone retained as logged diagnostic','Finite StopTime set to 300 seconds'}});
trainingcurriculum.write_json(fullfile(folder,'manifest.json'),manifest);
fprintf('Built independent continuous-flight model; no train/sim performed. Source unchanged.\n');
end
