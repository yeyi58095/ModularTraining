function report=shadow_learning_review(sessionDir,episode)
% Replay saved history without changing control/guard/agent/stage state.
% Advisory first phase of the JSON controller proposal; never activates actions.
arguments
    sessionDir (1,1) string
    episode (1,1) double {mustBeInteger,mustBePositive}
end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
if ~java.io.File(char(sessionDir)).isAbsolute(),sessionDir=fullfile(root,sessionDir);end
lock=System.IO.File.Open(char(fullfile(sessionDir,'supervisor.lock')), ...
    System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
lockGuard=onCleanup(@()lock.Dispose()); %#ok<NASGU>
status=jsondecode(fileread(fullfile(sessionDir,'status.json')));
assert(any(strcmp(status.state,{'paused','stopped','success','error'})),'Shadow:Active','Run must be stopped.');
file=fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',episode));
sha=checkpointreview.sha256(file);[history,n]=checkpoint_resume_state(file);
assert(n==episode);
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),true);
state=jsondecode(fileread(fullfile(sessionDir,'curriculum_state.json')));
completed=state.completed;if ~iscell(completed),completed=num2cell(completed);end
rule=struct('schema_version',1,'window',100,'patience',2, ...
    'reward_ratio',.6,'steps_ratio',.6,'min_reference_reward',1000,'min_reference_steps',1400);
if isfile(fullfile(sessionDir,'training_guard.json'))
    rule=jsondecode(fileread(fullfile(sessionDir,'training_guard.json')));
end
rows={};
for endpoint=100:100:n
    stageIndex=1;startEpisode=0;
    for j=1:numel(completed)
        if endpoint>completed{j}.end_episode
            stageIndex=j+1;startEpisode=completed{j}.end_episode;
        end
    end
    r=history.EpisodeReward(1:endpoint);s=history.EpisodeSteps(1:endpoint);
    decision=trainingcurriculum.decide(plan.stages{stageIndex},r(startEpisode+1:end),s(startEpisode+1:end));
    health=trainingguard.assess(r,s,startEpisode,rule);
    action='observe';
    if ~strcmp(decision.action,'continue'),action='review_saved_curriculum_decision';
    elseif health.suspected_regression,action='request_paired_validation';
    elseif endpoint-startEpisode>=1000 && ~any(s(startEpisode+1:end)>=3000)
        action='inspect_early_termination';
    end
    rows{end+1}=struct('episode',endpoint,'stage_index',stageIndex, ...
        'stage_start_episode',startEpisode,'recommendation',action, ...
        'curriculum',decision,'health',health); %#ok<AGROW>
end
report=struct('schema_version',1,'advisory_only',true,'actions_executed',0, ...
    'source_checkpoint_sha256',sha,'through_episode',n,'rules',rule,'rows',{rows}, ...
    'limitation','No causal diagnosis, automatic learning-rate change, rollback, validation or launch.');
folder=fullfile(root,'artifacts','incoming');if ~isfolder(folder),mkdir(folder);end
out=tempname(folder);mkdir(out);report.outputDir=out;
assert(strcmp(sha,checkpointreview.sha256(file)));
trainingcurriculum.write_json(fullfile(out,'shadow-review.json'),report);
fprintf('Shadow replay through %d; no actions executed. %s\n',n,out);
end
