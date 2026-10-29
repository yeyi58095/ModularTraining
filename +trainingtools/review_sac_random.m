function report=review_sac_random(sessionDir,episode)
% Bounded frozen CPU suite on held-out route seeds, including calm retention.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'runtime'));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
assert(strcmp(plan.model,'sac_paper64'),'Review:Model','Wrong experiment.');
state=jsondecode(fileread(fullfile(sessionDir,'curriculum_state.json')));
stage=plan.stages{state.stage_index};
[~,finalEpisode]=checkpoint_resume_state(fullfile(sessionDir,'Agent_Final.mat'));
assert(episode==finalEpisode,'Review:Episode', ...
    'Review the current final episode %d for this stage gate. Historical checkpoints use compare_training_checkpoints directly.',finalEpisode);
report=compare_training_checkpoints(sessionDir,episodes=[],includeLatest=false,finalCheckpoint=true, ...
    stages=unique([1 state.stage_index]),seeds=stage.frozen_gate.seeds(:)', ...
    maxSteps=3000,routeMetrics=true,useExploration=false);
fprintf('Frozen evaluation complete. No training started; retry only after reviewing results.\n');
end
