function result = verify_training_session(sessionDir)
% 停止實驗驗證：檢查可讀 checkpoint、實際回合數及課程階段相容性。
% 回傳驗證結果；以排他鎖避免與 supervisor 同時存取，不 train、不 sim、不改課程進度。
% Read a stopped experiment's checkpoint and curriculum without training.
root=fileparts(fileparts(mfilename('fullpath'))); old=path;
guard=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
sessionDir=char(sessionDir);
if ~java.io.File(sessionDir).isAbsolute(), sessionDir=fullfile(root,sessionDir); end
sessionDir=char(java.io.File(sessionDir).getCanonicalPath());
lock=System.IO.File.Open(fullfile(sessionDir,'supervisor.lock'), ...
    System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@() lock.Dispose()); %#ok<NASGU>
state=jsondecode(fileread(fullfile(sessionDir,'curriculum_state.json')));
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
cfg=jsondecode(fileread(fullfile(sessionDir,'control.json')));
assert(strcmp(cfg.sessionDir,sessionDir),'Migration:Path','control.json points to another session.');
files=dir(fullfile(sessionDir,'**','*.mat')); paths={}; times=[];
for i=1:numel(files)
    file=fullfile(files(i).folder,files(i).name);
    relative=file(numel(sessionDir)+2:end);
    if (strcmp(files(i).name,'Agent_Final.mat') || ~isempty(regexp(files(i).name,'^Agent_?\d+\.mat$','once'))) ...
            && isempty(regexp(relative,'(^|[\\/])runs[\\/]','once'))
        paths{end+1}=file; times(end+1)=files(i).datenum; %#ok<AGROW>
    end
end
assert(~isempty(paths),'Migration:Checkpoint','No saved checkpoints; refusing a fresh start.');
[~,order]=sort(times,'descend'); checkpoint=checkpoint_select_agent(paths(order));
[~,episode]=checkpoint_resume_state(checkpoint);
assert(state.stage_index>=1 && state.stage_index<=numel(plan.stages) && ...
    state.start_episode<=episode,'Migration:State','Checkpoint cannot support saved curriculum progress.');
result=struct('sessionDir',sessionDir,'checkpoint',checkpoint,'episode',episode, ...
    'stageIndex',state.stage_index,'stageId',plan.stages{state.stage_index}.id);
disp(result);
fprintf('Verified readable PPO checkpoint and stage position. No training started.\n');
end
