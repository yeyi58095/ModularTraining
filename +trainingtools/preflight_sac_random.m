function result=preflight_sac_random(device,workers)
% Read-only capability check, no pool/training/session created.
if nargin<1,device='gpu';end
if nargin<2,workers=6;end
root=fileparts(fileparts(mfilename('fullpath')));
assert(~isempty(ver('rl')) && license('test','Distrib_Computing_Toolbox'), ...
    'Preflight:License','RL and Parallel Computing Toolbox licenses required.');
cluster=parcluster('Processes');
assert(cluster.NumWorkers>=workers,'Preflight:Workers','Local profile supports fewer than requested workers.');
gpuName='not requested';
if strcmp(device,'gpu')
    assert(gpuDeviceCount('available')>0,'Preflight:GPU','No supported available GPU.');
    d=gpuDevice;gpuName=d.Name;
end
spec=trainingmodels.load_profile('sac_paper64');
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
agent=trainingmodels.build_agent(spec,obs,act,device);trainingmodels.validate_agent(agent,spec);
trainingcurriculum.load_plan(fullfile(root,'experiments','sac_random_route_v1','curriculum.json'),true);
trainingenv.registry(root,'spatial_v2');
result=struct('release',version('-release'),'workers_requested',workers,'gpu',gpuName, ...
    'scope','capability/build only; no pool allocation,training,throughput or convergence verification');
disp(result);
end
