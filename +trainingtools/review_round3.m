function reports=review_round3(sessionDir)
% Four CPU simulations; never train/resume, mutate checkpoints, or change gates.
arguments
    sessionDir (1,1) string
end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
% Fail before the first simulation if the chosen pair is unavailable.
for ep=[16000 17200]
    assert(isfile(fullfile(sessionDir,'checkpoints',sprintf('Agent%d.mat',ep))), ...
        'Round3:Checkpoint','Missing Agent%d.mat; do not substitute silently.',ep);
end
reports=cell(1,2);
for k=1:2
    reports{k}=compare_training_checkpoints(sessionDir, ...
        episodes=[16000 17200],includeLatest=false,stages=3,seeds=101, ...
        maxSteps=3000,useExploration=(k==2),explorationStdScale=1, ...
        diagnostics=true,routeMetrics=true);
    disp(reports{k}.outputDir);
    disp(jsonencode(reports{k}.summary,PrettyPrint=true));
    disp(jsonencode(reports{k}.results,PrettyPrint=true));
end
fprintf('Four diagnostic replays only. One fixed route/seed is not a reliability evaluation.\n');
end
