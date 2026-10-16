function test_exploration_scale(checkpointFile,traceFile)
% Frozen-policy replay plus two five-step CPU sims; never train.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
sourceHash=checkpointreview.sha256(checkpointFile);[~,ep]=checkpoint_resume_state(checkpointFile);
x=load(checkpointFile);if isfield(x,'saved_agent'),agent=x.saved_agent;else,agent=x.Agent_Stage2;end
actor=getActor(agent);actor.UseDevice='cpu';s=actor.State;for k=1:numel(s),s{k}=0*s{k};end;actor.State=s;
scaled=checkpointreview.scale_exploration_actor(actor,.5);
d=load(traceFile,'experience');names=fieldnames(d.experience.Observation);obs=reshape(d.experience.Observation.(names{1}).Data,10,[]);
for k=1:min(150,size(obs,2))
 [a,sa]=evaluate(actor,{obs(:,k)});[b,sb]=evaluate(scaled,{obs(:,k)});
 assert(abs(double(a{1})-double(b{1}))<1e-6);
 assert(abs(.5*double(a{2})-double(b{2}))<1e-6);
 actor.State=cellfun(@dlarray,sa,'UniformOutput',false);scaled.State=cellfun(@dlarray,sb,'UniformOutput',false);
end
assert(isequaln(getLearnableParameters(actor),getLearnableParameters(scaled)));
try,compare_training_checkpoints("missing",useExploration=false,explorationStdScale=.5);error('Test:MissingError','Expected validation');catch err,assert(strcmp(err.identifier,'Evaluation:ExplorationScale'));end
info=retry(curriculum=fullfile(root,'experiments','progressive_v2','curriculum.json'),start=false,device="cpu");
trainingcurriculum.write_json(fullfile(info.sessionDir,'status.json'),struct('state','paused','attempt',0));
mkdir(fullfile(info.sessionDir,'checkpoints'));copyfile(checkpointFile,fullfile(info.sessionDir,'checkpoints',sprintf('Agent%d.mat',ep)));
a=compare_training_checkpoints(info.sessionDir,episodes=ep,includeLatest=false,stages=4,seeds=601,maxSteps=5,useExploration=true,explorationStdScale=.5);
b=compare_training_checkpoints(info.sessionDir,episodes=ep,includeLatest=false,stages=4,seeds=601,maxSteps=5,useExploration=true,explorationStdScale=.5);
assert(a.exploration_std_scale==.5 && b.exploration_std_scale==.5 && a.weights_unchanged && b.weights_unchanged);
x=load(fullfile(a.outputDir,a.results{1}.trace));y=load(fullfile(b.outputDir,b.results{1}.trace));names=fieldnames(x.experience.Action);key=names{1};assert(isequaln(x.experience.Action.(key).Data,y.experience.Action.(key).Data));
assert(strcmp(sourceHash,checkpointreview.sha256(checkpointFile)));
fprintf('PASS 150-step paired replay: means unchanged, std halved, weights preserved; two seeded five-step sims repeat; source hash unchanged. No training.\n');
end
