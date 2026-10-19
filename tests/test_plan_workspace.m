function test_plan_workspace()
% 課程工作區測試：驗證共享 JSON／assets、舊入口轉址與 run 的不可變課程快照。
% 只生成輸入及 start=false 的 run；GPU 設定僅做準備，不執行 GPU 訓練。
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
inputs=trainingtools.prepare_progressive_training();
assert(strcmp(inputs.planFile,fullfile(root,'experiments','progressive_v1','curriculum.json')));
assert(strcmp(inputs.straightFile,fullfile(root,'experiments','progressive_v1','assets','straight.mat')));
warning('off','Curriculum:Moved'); guard=onCleanup(@() warning('on','Curriculum:Moved')); %#ok<NASGU>
assert(strcmp(resolve_curriculum_path('curricula/progressive_v1.json'),inputs.planFile));
cfg=jsondecode(fileread(fullfile(root,'configs','lab_gpu6.json'))); args=namedargs2cell(cfg);
info=retry(args{:},start=false);
assert(strcmp(fileparts(info.sessionDir),fullfile(root,'experiments','progressive_v1','runs')));
assert(isfile(fullfile(info.sessionDir,'curriculum_state.json'))==false);
assert(isfile(fullfile(info.sessionDir,'curriculum_assets','stage001.mat')));
snapshot=fileread(fullfile(info.sessionDir,'curriculum.json'));
again=retry(resume=info.sessionDir,start=false);
assert(strcmp(again.sessionDir,info.sessionDir));
assert(strcmp(snapshot,fileread(fullfile(info.sessionDir,'curriculum.json'))));
fprintf('PASS plan folder, assets, legacy alias, GPU config preparation, immutable resume; no training.\n');
end
