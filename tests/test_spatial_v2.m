function test_spatial_v2()
% Read the actual bundled charts, compare all chart scripts, then test formulas.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
assert(~bdIsLoaded('FAFA_Simulation'));
oldFolder=pwd;oldPath=path;guard=onCleanup(@()restore(oldFolder,oldPath)); %#ok<NASGU>
[v1File,v1Dir]=trainingenv.registry(root,'spatial_v1');
[v2File,v2Dir]=trainingenv.registry(root,'spatial_v2');
v1=trainingenv.verify(v1File,v1Dir);v2=trainingenv.verify(v2File,v2Dir);
assert(strcmp(v2.parent_model_sha256,v1.files.sha256));
cd(v1Dir);load_system(fullfile(v1Dir,v1.model_file));a=scripts();close_system('FAFA_Simulation',0);
cd(v2Dir);load_system(fullfile(v2Dir,v2.model_file));b=scripts();
assert(isequal(a.keys,b.keys));changed={};
for key=a.keys,if ~strcmp(a(key{1}),b(key{1})),changed{end+1}=key{1};end,end %#ok<AGROW>
assert(isequal(sort(changed),sort({'FAFA_Simulation/OBSERVATION/MATLAB Function13', ...
    'FAFA_Simulation/OBSERVATION/MATLAB Function22'})));
[~,definition]=checkpointreview.instrument_reward('FAFA_Simulation');
assert(strcmp(definition.reward_version,'spatial_reward_v2'));
close_system('FAFA_Simulation',0);
fixture=tempname(fullfile(root,'tests','output'));mkdir(fixture);addpath(fixture);
write(fullfile(fixture,'cross_v2.m'),strrep(b('FAFA_Simulation/OBSERVATION/MATLAB Function13'),'fcn(','cross_v2('));
write(fullfile(fixture,'bonus_v2.m'),strrep(b('FAFA_Simulation/OBSERVATION/MATLAB Function22'),'fcn(','bonus_v2('));
[dm,kt,dis]=ndgrid([0 5 9.999 10 10.001 15 30 50],[0 .01 .1 1.2],[0 30 150 200]);
d=dm(:);kt=kt(:);dis=dis(:);n=numel(d);parts=zeros(n,10);indicator=zeros(n,1);
for i=1:n
    parts(i,1)=.2*(1-abs(cross_v2(kt(i),d(i)/30)));
    indicator(i)=bonus_v2(d(i)/30,dis(i));
    parts(i,8)=.1*(1+indicator(i));
end
[expected,expectedParts]=checkpointreview.spatial_reward_candidate(zeros(n,10),d,.2);
assert(max(abs(parts-expectedParts),[],'all')<1e-12);
t=(0:n)'*.1;ds=Simulink.SimulationData.Dataset;
names={'cross_track','distance_rate','heading','curvature_distance','roll_rate','yaw_rate', ...
    'yaw_tracking','distance_bonus','action_limit','action_change'};
for i=1:10,ds=add(ds,['reward_' names{i}],[parts(1,i);parts(:,i)],t);end
extra={'reward_total',expected;'guidance_d',d;'reward_normalized_d',d/30; ...
    'distance_to_window_target',dis;'reward_bonus_indicator',indicator;'reward_normalized_curvature',kt};
for i=1:size(extra,1),v=extra{i,2};ds=add(ds,extra{i,1},[v(1);v],t);end
experience=struct('Reward',timeseries(expected,t(1:end-1)));
audit=checkpointreview.reward_breakdown(experience,ds,'spatial_reward_v2');
assert(audit.max_per_step_residual<1e-12 && audit.curvature_gate.applied_fraction==0);
assert(audit.bonus.distance_band_sum==0);
try
    checkpointreview.reward_breakdown(experience,ds,'legacy_spatial');
    error('Test:ExpectedFailure','Version mismatch accepted.');
catch err,assert(strcmp(err.identifier,'RewardAudit:Bonus'));end
info=retry(environment="spatial_v2",start=false,device="cpu");
[~,bound]=trainingenv.resolve(info.sessionDir);assert(strcmp(bound.reward_version,'spatial_reward_v2'));
fprintf('PASS spatial_v2: exactly two charts changed, %d distance/curvature/target cases, versioned audit and new-run snapshot.\n',n);
end
function result=scripts()
result=containers.Map('KeyType','char','ValueType','char');
charts=find(sfroot,'-isa','Stateflow.EMChart');
for i=1:numel(charts)
    if startsWith(charts(i).Path,'FAFA_Simulation/'),result(charts(i).Path)=charts(i).Script;end
end
end
function write(file,value)
fid=fopen(file,'w');c=onCleanup(@()fclose(fid));fprintf(fid,'%s',value); %#ok<NASGU>
end
function ds=add(ds,name,v,t)
s=Simulink.SimulationData.Signal;s.Name=name;s.Values=timeseries(v,t);ds=ds.addElement(s);
end
function restore(folder,p)
if bdIsLoaded('FAFA_Simulation'),close_system('FAFA_Simulation',0);end
cd(folder);path(p);
end
