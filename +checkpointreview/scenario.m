function data=scenario(stage,sessionDir,seed)
% 配對評估情境：按 seed 建立 MAT／固定／random 軌跡，另用偏移 seed 抽樣整數風場。
% 回傳路徑、速度、風與識別資料；恢復呼叫者 RNG，相同 seed 可跨風場配對路徑。
% Preserve caller RNG and pair paths across wind conditions.
old=rng; cleanup=onCleanup(@() rng(old)); %#ok<NASGU>
rng(seed,'twister');
switch stage.trajectory.type
    case 'mat'
        data=trainingcurriculum.load_trajectory(stage.trajectory,sessionDir);
    case 'fixed_builtin'
        [data.waypoints,data.velocity]=checkpointreview.fixed_path();
    case 'random'
        [data.waypoints,data.velocity]=checkpointreview.random_path();
    otherwise
        error('Evaluation:Trajectory','Unsupported trajectory type.');
end
rng(mod(double(seed)+104729,2^32),'twister');
data.wind=[randi(stage.wind.east_mps(:)'),randi(stage.wind.north_mps(:)'), ...
    randi(stage.wind.turbulence(:)')];
data.id=stage.id; data.seed=seed;
end
