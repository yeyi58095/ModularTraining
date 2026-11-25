function outputDir = compare_startup_models(beforeModel, fixedModel)
% Historical frozen A/B, using the two verified October 10 environment revisions.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
base = fullfile(root,'diagnostic_packages');
if nargin < 1
    beforeModel = fullfile(base,'FAFA_Simulation_before_startup_fix.slx');
end
if nargin < 2
    fixedModel = fullfile(base,'FAFA_Simulation_after_startup_fix.slx');
end
models = {trainingtools.local_data_path(root,beforeModel), ...
    trainingtools.local_data_path(root,fixedModel)};
expectedHashes = {'0f59a6b6e1d042edebe85fdf13a4ab6f9b30a774569dc752f8b69817cf3b1537', ...
    'fe597eafe96da6ea424ea58b7ab8fab32c734ee7e7e572243c5995a34b38f341'};
for i = 1:numel(models)
    assert(strcmpi(checkpointreview.sha256(models{i}),expectedHashes{i}), ...
        'Historical model SHA-256 differs: %s',models{i});
end
assert(~bdIsLoaded('FAFA_Simulation'),'Close FAFA_Simulation before starting this comparison.');
bundle = fullfile(base,'lab_recovery_e44b46f8');
oldFolder = pwd;
oldPath = path;
oldRng = rng;
global TARGET_SPEED DT WAYPOINT_SPACING
oldGlobals = {TARGET_SPEED,DT,WAYPOINT_SPACING};
hadAgent = evalin('base','exist(''Agent_Stage2'',''var'') == 1');
oldAgent = [];
if hadAgent
    oldAgent = evalin('base','Agent_Stage2');
end
cleanup = onCleanup(@() restore(oldFolder,oldPath,oldRng,oldGlobals,hadAgent,oldAgent)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
TARGET_SPEED=15; DT=.1; WAYPOINT_SPACING=1.5;
data=load(fullfile(bundle,'reports','evaluation_20261010_183235_tp0d559eeb','scenarios.mat'),'scenarios');
scenario=data.scenarios{1};
[~,outputDir] = diagnostic_paths(mfilename);
results={};
cfg=Simulink.fileGenControl('getConfig'); cg=onCleanup(@()Simulink.fileGenControl('setConfig','config',cfg)); %#ok<NASGU>
work=fullfile(outputDir,'simulation'); mkdir(work); Simulink.fileGenControl('set','CacheFolder',fullfile(work,'cache'),'CodeGenFolder',fullfile(work,'code'),'createDir',true);
for variant=1:2
    folder=fullfile(work,sprintf('v%d',variant)); mkdir(folder);
    copyfile(models{variant},fullfile(folder,'FAFA_Simulation.slx')); cd(folder);
    load_system(fullfile(folder,'FAFA_Simulation.slx'));
    settings=checkpointreview.prepare_model('FAFA_Simulation',true,true);
    for ep=[10600 10700]
        file=fullfile(bundle,'checkpoints',sprintf('Agent%d.mat',ep)); hash=checkpointreview.sha256(file);
        vars=whos('-file',file); name='saved_agent'; if ~any(strcmp({vars.name},name)), name='Agent_Stage2'; end
        d=load(file,name); agent=d.(name); a=getActor(agent); a.UseDevice='cpu'; agent=setActor(agent,a);
        c=getCritic(agent); c.UseDevice='cpu'; agent=setCritic(agent,c); agent.UseExplorationPolicy=false;
        beforeA=getLearnableParameters(getActor(agent)); beforeC=getLearnableParameters(getCritic(agent));
        assignin('base','Agent_Stage2',agent);
        env=rlSimulinkEnv('FAFA_Simulation','FAFA_Simulation/RL Agent',getObservationInfo(agent),getActionInfo(agent),'UseFastRestart','off');
        env.ResetFcn=@(in)reset(in,scenario); rng(101,'twister');
        fprintf('START variant=%d ep=%d\n',variant,ep);
        experience=sim(env,agent,rlSimulationOptions('MaxSteps',200,'NumSimulations',1,'UseParallel',false,'StopOnError','on'));
        assert(isequaln(beforeA,getLearnableParameters(getActor(agent))) && isequaln(beforeC,getLearnableParameters(getCritic(agent))));
        assert(strcmp(hash,checkpointreview.sha256(file)));
        row=checkpointreview.summarize(experience,200); row.variant=variant; row.episode=ep;
        save(fullfile(outputDir,sprintf('startup_v%d_ep%d.mat',variant,ep)),'experience');
        results{end+1}=row; disp(row);
        trainingcurriculum.write_json(fullfile(outputDir,'startup_ab.json'),results);
    end
    clear settings; close_system('FAFA_Simulation',0);
end
end
function in=reset(in,s)
for n=["wind_E0","wind_N0","wind_turbulance_value0"], in=setVariable(in,n,0,'Workspace','FAFA_Simulation'); end
in=setVariable(in,'waypoints',s.waypoints,'Workspace','FAFA_Simulation');
in=setVariable(in,'velocity',s.velocity,'Workspace','FAFA_Simulation');
end
function restore(folder,oldPath,r,oldGlobals,hadAgent,oldAgent)
if bdIsLoaded('FAFA_Simulation'), close_system('FAFA_Simulation',0); end
cd(folder); path(oldPath); rng(r);
global TARGET_SPEED DT WAYPOINT_SPACING
TARGET_SPEED=oldGlobals{1}; DT=oldGlobals{2}; WAYPOINT_SPACING=oldGlobals{3};
if hadAgent
    assignin('base','Agent_Stage2',oldAgent);
else
    evalin('base','clear Agent_Stage2');
end
end
