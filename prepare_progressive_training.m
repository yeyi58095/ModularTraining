function info = prepare_progressive_training()
% 六階段課程準備：生成可重建的直線／S 彎 MAT，並驗證共享 curriculum.json。
% 回傳課程與輸入位置；內容不同的既有 MAT 拒絕覆寫，不啟動正式訓練。
% Generate reproducible starter trajectories and validate the six-stage plan.
% No training, pool, or experiment is started. Existing differing MATs are refused.
root=fileparts(mfilename('fullpath')); old=path;
guard=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,'-begin');
folder=fullfile(root,'experiments','progressive_v1','assets');
if ~isfolder(folder), mkdir(folder); end
distance=(0:1.5:6000)'; % 15 m/s * 0.1 s; longer than a 300-second episode.
waypoints=[50+distance,zeros(size(distance)),70*ones(size(distance))];
velocity=repmat([15 0 0],numel(distance),1);
straight=fullfile(folder,'straight.mat'); saveInput(straight,waypoints,velocity);
heading=deg2rad(25)*sin(2*pi*distance/2400);
waypoints=[50+cumtrapz(distance,cos(heading)),cumtrapz(distance,sin(heading)),70*ones(size(distance))];
velocity=[15*cos(heading),15*sin(heading),zeros(size(heading))];
gentle=fullfile(folder,'gentle_s.mat'); saveInput(gentle,waypoints,velocity);
planFile=fullfile(root,'experiments','progressive_v1','curriculum.json');
plan=curriculum_plan(planFile);
info=struct('planFile',planFile,'straightFile',straight,'gentleFile',gentle, ...
    'model',plan.model,'stages',numel(plan.stages));
fprintf('Inputs prepared. No training started. MAT inputs are ignored by Git and can be regenerated on either PC.\n');
end

function saveInput(file,waypoints,velocity)
% 既有 MAT 先比對內容，一致則沿用，不一致拒絕覆寫；新檔保存軌跡與速度。
if isfile(file)
    current=load(file,'waypoints','velocity');
    assert(isfield(current,'waypoints') && isfield(current,'velocity') && ...
        isequaln(current.waypoints,waypoints) && isequaln(current.velocity,velocity), ...
        'Curriculum:InputExists','Existing input differs; refusing to overwrite: %s',file);
else
    save(file,'waypoints','velocity');
end
end
