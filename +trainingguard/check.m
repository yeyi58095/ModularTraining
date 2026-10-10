function terminal=check(sessionDir,agentFile)
% Called only at saved boundaries; no process killing or agent modification.
terminal=[]; rulesFile=fullfile(sessionDir,'training_guard.json');
if ~isfile(rulesFile) || strlength(string(agentFile))==0, return; end
rules=jsondecode(fileread(rulesFile));
[history,episode]=checkpoint_resume_state(agentFile);
state=jsondecode(fileread(fullfile(sessionDir,'curriculum_state.json')));
plan=trainingcurriculum.load_plan(fullfile(sessionDir,'curriculum.json'),false);
assessment=trainingguard.assess(history.EpisodeReward,history.EpisodeSteps,state.start_episode,rules);
assessment.episode=episode; assessment.stage_index=state.stage_index;
assessment.stage_id=plan.stages{state.stage_index}.id;
assessment.checkpoint=char(agentFile); assessment.reason='continue';
validateattributes(rules.origin_episode,{'numeric'},{'scalar','integer','nonnegative','<=',episode});
validateattributes(rules.max_additional_episodes,{'numeric'},{'scalar','integer','positive','finite'});
if assessment.suspected_regression, assessment.reason='suspected_regression';
elseif episode-rules.origin_episode>=rules.max_additional_episodes, assessment.reason='recovery_budget'; end
% Persist pause until a new branch is deliberately prepared. retry cannot
% accidentally bypass it merely because guard state was recalculated.
stateFile=fullfile(sessionDir,'training_guard_state.json');
if isfile(stateFile)
    previous=jsondecode(fileread(stateFile));
    if isfield(previous,'paused') && previous.paused
        assessment.reason=previous.reason;
    end
end
assessment.paused=~strcmp(assessment.reason,'continue');
% Keep a labelled training-metric candidate, never claim evaluation-best.
if assessment.reference_end_episode==episode
    candidateDir=fullfile(sessionDir,'health_candidates');
    if ~isfolder(candidateDir), mkdir(candidateDir); end
    candidate=fullfile(candidateDir,sprintf('Candidate%d.mat',episode));
    if ~isfile(candidate)
        temporary=[tempname(candidateDir) '.mat']; copyfile(agentFile,temporary);
        assert(strcmp(checkpointreview.sha256(agentFile),checkpointreview.sha256(temporary)), ...
            'Guard:Copy','Candidate copy verification failed.');
        movefile(temporary,candidate);
    end
    candidateInfo=assessment; candidateInfo.label='training_window_candidate_not_evaluation_best';
    trainingcurriculum.write_json(fullfile(candidateDir,sprintf('Candidate%d.json',episode)),candidateInfo);
end
trainingcurriculum.write_json(stateFile,assessment);
if assessment.paused
    terminal=struct('success',false,'pause',true,'episodes',episode, ...
        'averageReward',mean(history.EpisodeReward(max(1,end-49):end)), ...
        'finalAgent',char(agentFile),'successAgent','','curriculumDecision','pause', ...
        'curriculumReason',assessment.reason,'stageId',assessment.stage_id, ...
        'stageIndex',state.stage_index,'pauseReason',assessment.reason);
    trainingcurriculum.write_json(fullfile(sessionDir,'curriculum_outcome.json'),terminal);
    fprintf('Guard paused after saved episode %d: %s. No rollback.\n',episode,assessment.reason);
end
end
