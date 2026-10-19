function test_continuous_flight_model()
% Read-only structural verification; no train or flight simulation.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
source=fullfile(root,'environments','spatial_v2','FAFA_Simulation.slx');
folder=fullfile(root,'simulations','continuous_flight');
target=fullfile(folder,'FAFA_ContinuousFlight.slx');
meta=jsondecode(fileread(fullfile(folder,'manifest.json')));
assert(strcmpi(checkpointreview.sha256(source),meta.source_sha256));
assert(strcmpi(checkpointreview.sha256(target),meta.sha256));
assert(~bdIsLoaded('FAFA_Simulation') && ~bdIsLoaded('FAFA_ContinuousFlight'));
load_system(source);load_system(target);
guard=onCleanup(@()closeModels()); %#ok<NASGU>
a='FAFA_Simulation';b='FAFA_ContinuousFlight';
sourceDone=get_param([a '/isdone'],'PortHandles');sourceAgent=get_param([a '/RL Agent'],'PortHandles');
line=get_param(sourceAgent.Inport(3),'Line');
assert(get_param(line,'SrcPortHandle')==sourceDone.Outport(1));
agent=get_param([b '/RL Agent'],'PortHandles');constant=get_param([b '/EpisodeDoneDisabled'],'PortHandles');
assert(get_param(get_param(agent.Inport(3),'Line'),'SrcPortHandle')==constant.Outport(1));
assert(strcmp(get_param([b '/EpisodeDoneDisabled'],'Value'),'0'));
assert(strcmp(get_param([b '/EpisodeDoneDisabled'],'OutDataTypeStr'),'boolean'));
done=get_param([b '/isdone'],'PortHandles');sink=get_param([b '/IsDoneDiagnostic'],'PortHandles');
assert(get_param(get_param(sink.Inport(1),'Line'),'SrcPortHandle')==done.Outport(1));
assert(strcmp(get_param(b,'StopTime'),'300'));
assert(strcmp(get_param([a '/RL Agent'],'Agent'),get_param([b '/RL Agent'],'Agent')));
% All embedded dynamics, reward and termination MATLAB charts retain exact source.
chartsA=find(sfroot,'-isa','Stateflow.EMChart','-regexp','Path',['^' a '/']);
chartsB=find(sfroot,'-isa','Stateflow.EMChart','-regexp','Path',['^' b '/']);
assert(~isempty(chartsA) && numel(chartsA)==numel(chartsB));
for k=1:numel(chartsA)
    suffix=extractAfter(string(chartsA(k).Path),strlength(a));
    other=find(sfroot,'-isa','Stateflow.EMChart','Path',char(string(b)+suffix));
    assert(isscalar(other) && strcmp(chartsA(k).Script,other.Script));
end
try
    trainingtools.build_continuous_flight();error('Test:ExpectedRefusal','Overwrite accepted');
catch err
    assert(strcmp(err.identifier,'Continuous:Exists'));
end
assert(strcmpi(checkpointreview.sha256(source),meta.source_sha256));
assert(strcmpi(checkpointreview.sha256(target),meta.sha256));
fprintf('PASS independent SLX loads, source done preserved, false agent done, diagnostic logging, unchanged charts and overwrite refusal. No flight sim/train.\n');
end
function closeModels()
close_system('FAFA_ContinuousFlight',0);close_system('FAFA_Simulation',0);
end
