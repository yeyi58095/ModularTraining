function test_plan_workspace()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
inputs=prepare_progressive_training();
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
