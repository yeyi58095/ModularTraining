function report=simulate_continuous_flight(checkpoint,scenarioFile,stageId,seed)
% Frozen 300-second replay of a saved scenario in the independent continuous model.
% This is not a standard pass/fail evaluation or a training entry point.
arguments
    checkpoint (1,1) string
    scenarioFile (1,1) string
    stageId (1,1) string
    seed (1,1) double {mustBeInteger,mustBeNonnegative}
end
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;oldFolder=pwd;oldRng=rng;
restore=onCleanup(@()restoreCaller(oldPath,oldFolder,oldRng)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
global TARGET_SPEED DT WAYPOINT_SPACING
oldGlobals={TARGET_SPEED,DT,WAYPOINT_SPACING};
globalsGuard=onCleanup(@()restoreGlobals(oldGlobals)); %#ok<NASGU>
TARGET_SPEED=15;DT=.1;WAYPOINT_SPACING=1.5;
mdl='FAFA_ContinuousFlight';
assert(~bdIsLoaded(mdl),'Continuous:Loaded','Close the continuous model first.');
source=fullfile(root,'simulations','continuous_flight',[mdl '.slx']);
meta=jsondecode(fileread(fullfile(fileparts(source),'manifest.json')));
assert(strcmpi(checkpointreview.sha256(source),meta.sha256));
agentHash=checkpointreview.sha256(checkpoint);
data=load(scenarioFile,'scenarios');selected=[];
for k=1:numel(data.scenarios)
    candidate=data.scenarios{k};
    if strcmp(candidate.id,stageId) && candidate.seed==seed,selected=candidate;break;end
end
assert(~isempty(selected),'Continuous:Scenario','Requested saved scenario not found.');
vars=whos('-file',checkpoint);name='saved_agent';
if ~any(strcmp({vars.name},name)),name='Agent_Stage2';end
data=load(checkpoint,name);agent=data.(name);agent.UseExplorationPolicy=false;
actor=getActor(agent);actor.UseDevice='cpu';agent=setActor(agent,actor);
critics=getCritic(agent);for k=1:numel(critics),critics(k).UseDevice='cpu';end
agent=setCritic(agent,critics);
hadAgent=evalin('base',"exist('Agent_Stage2','var')==1");oldAgent=[];
if hadAgent,oldAgent=evalin('base','Agent_Stage2');end
restoreAgentGuard=onCleanup(@()restoreAgent(hadAgent,oldAgent)); %#ok<NASGU>
assignin('base','Agent_Stage2',agent);
folder=fullfile(root,'artifacts','incoming');
if ~isfolder(folder),mkdir(folder);end
out=tempname(folder);mkdir(out);
copyfile(source,fullfile(out,[mdl '.slx']));
cd(out);load_system(fullfile(out,[mdl '.slx']));
modelGuard=onCleanup(@()close_system(mdl,0)); %#ok<NASGU>
settings=checkpointreview.prepare_model(mdl,true,true); %#ok<NASGU>
set_param([mdl '/IsDoneDiagnostic'],'Commented','off');
env=rlSimulinkEnv(mdl,[mdl '/RL Agent'],getObservationInfo(agent),getActionInfo(agent),'UseFastRestart','off');
env.ResetFcn=@(in)resetScenario(in,selected,mdl);
rng(seed,'twister');
experience=sim(env,agent,rlSimulationOptions('MaxSteps',3000,'UseParallel',false,'StopOnError','on'));
simulationOutput=experience.SimulationInfo(1);
done=simulationOutput.get('isDoneDiagnostic');
assert(isa(done,'timeseries') && ~isempty(done.Data),'Continuous:Diagnostic','Original done signal missing.');
report=struct('standard_evaluation',false,'training',false,'steps',numel(experience.Reward.Data), ...
    'original_done_samples',nnz(done.Data),'stage',char(stageId),'seed',seed, ...
    'checkpoint_sha256',agentHash,'model_sha256',meta.sha256,'outputDir',out);
save(fullfile(out,'trace.mat'),'experience','done','selected','-v7.3');
assert(strcmp(agentHash,checkpointreview.sha256(checkpoint)) && strcmpi(meta.sha256,checkpointreview.sha256(source)));
trainingcurriculum.write_json(fullfile(out,'report.json'),report);disp(report);
end
function in=resetScenario(in,data,mdl)
names=["wind_E0","wind_N0","wind_turbulance_value0"];
for k=1:3,in=setVariable(in,names(k),data.wind(k),'Workspace',mdl);end
in=setVariable(in,'waypoints',data.waypoints,'Workspace',mdl);
in=setVariable(in,'velocity',data.velocity,'Workspace',mdl);
end
function restoreCaller(p,f,r)
cd(f);path(p);rng(r);
end
function restoreAgent(had,agent)
if had,assignin('base','Agent_Stage2',agent);else,evalin('base','clear Agent_Stage2');end
end
function restoreGlobals(values)
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=values{1};DT=values{2};WAYPOINT_SPACING=values{3};
end
