function plan = curriculum_plan(filename,varargin)
% 課程預檢入口：讀取 JSON、檢查欄位與選用的 MAT 輸入，顯示階段規劃。
% 回傳 plan；不建立實驗、不建 worker pool，也不啟動訓練。
% Validate and describe a JSON curriculum without starting training.
% checkFiles=false permits reviewing a template before its MAT inputs exist.
p=inputParser; p.addParameter('checkFiles',true); p.parse(varargin{:});
root=fileparts(mfilename('fullpath')); old=path; guard=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,'-begin');
plan=trainingcurriculum.load_plan(resolve_curriculum_path(filename),p.Results.checkFiles);
trainingmodels.load_profile(plan.model);
fprintf('Model retained across all stages: %s\n',plan.model);
for i=1:numel(plan.stages)
    s=plan.stages{i};
    fprintf('%d. %s | trajectory=%s | budget=%d stage episodes | on_limit=%s\n', ...
        i,s.id,s.trajectory.type,s.max_episodes,s.on_limit);
    fprintf('   advance_when: %s\n',jsonencode(s.advance_when));
end
fprintf('Plan validation only; no training or pool was started.\n');
end
