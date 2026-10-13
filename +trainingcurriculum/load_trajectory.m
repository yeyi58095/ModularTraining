function data = load_trajectory(spec,baseDir)
% MAT 軌跡讀取：依 JSON 指定的變數名稱載入 waypoints 與 velocity。
% 路徑相對於 baseDir；回傳有限實數 N×3 陣列，兩者大小必須一致，不生成或修改輸入檔。
% Only numeric N-by-3 position/velocity arrays are accepted for the FAFA model.
file=fullfile(baseDir,spec.file);
assert(isfile(file),'Curriculum:MissingTrajectory','Missing trajectory: %s',file);
dataIn=load(file,spec.waypoints_variable,spec.velocity_variable);
assert(isfield(dataIn,spec.waypoints_variable) && isfield(dataIn,spec.velocity_variable), ...
    'Curriculum:TrajectoryVariables','MAT file lacks the requested variables.');
data=struct('waypoints',dataIn.(spec.waypoints_variable),'velocity',dataIn.(spec.velocity_variable));
for key={'waypoints','velocity'}
    v=data.(key{1});
    assert(isnumeric(v) && isreal(v) && ismatrix(v) && size(v,2)==3 && size(v,1)>=2 && all(isfinite(v(:))), ...
        'Curriculum:TrajectoryShape','%s must be a finite real N-by-3 numeric array, N >= 2.',key{1});
end
assert(isequal(size(data.waypoints),size(data.velocity)), ...
    'Curriculum:TrajectoryShape','waypoints and velocity must have matching sizes.');
end
