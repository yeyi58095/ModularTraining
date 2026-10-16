function test_checkpoint_exploration(checkpointFile)
% Integration test with a supplied saved checkpoint; CPU simulations only.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
[~,ep]=checkpoint_resume_state(checkpointFile);sourceHash=checkpointreview.sha256(checkpointFile);
info=retry(curriculum=fullfile(root,'experiments','progressive_v2','curriculum.json'),start=false,device="cpu");
trainingcurriculum.write_json(fullfile(info.sessionDir,'status.json'),struct('state','paused','attempt',0));
mkdir(fullfile(info.sessionDir,'checkpoints'));
copyfile(checkpointFile,fullfile(info.sessionDir,'checkpoints',sprintf('Agent%d.mat',ep)));
a=compare_training_checkpoints(info.sessionDir,episodes=ep,includeLatest=false,stages=4,seeds=601,maxSteps=5);
b=compare_training_checkpoints(info.sessionDir,episodes=ep,includeLatest=false,stages=4,seeds=601,maxSteps=5,useExploration=true);
c=compare_training_checkpoints(info.sessionDir,episodes=ep,includeLatest=false,stages=4,seeds=601,maxSteps=5,useExploration=true);
assert(~a.use_exploration && b.use_exploration && c.use_exploration);
assert(a.weights_unchanged && b.weights_unchanged && c.weights_unchanged);
sa=load(fullfile(a.outputDir,'scenarios.mat'),'scenarios');sb=load(fullfile(b.outputDir,'scenarios.mat'),'scenarios');assert(isequaln(sa,sb));
xa=load(fullfile(a.outputDir,a.results{1}.trace));xb=load(fullfile(b.outputDir,b.results{1}.trace));xc=load(fullfile(c.outputDir,c.results{1}.trace));
assert(~isequaln(xa.experience.Action,xb.experience.Action));
names=fieldnames(xb.experience.Action);key=names{1};assert(isequaln(xb.experience.Action.(key).Data,xc.experience.Action.(key).Data));
assert(strcmp(sourceHash,checkpointreview.sha256(checkpointFile)));
fprintf('PASS default deterministic, exploratory actions differ, seeded repeat, paired paths, checkpoint/weights preserved. Three five-step CPU sims; no training.\n');
end
