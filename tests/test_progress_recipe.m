function test_progress_recipe()
% Verify environment pinning before touching any parent session; no training.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
s=jsondecode(fileread(fullfile(root,'configs','recovery_31600_progress_window.json')));
assert(s.checkpoint_episode==31600 && s.max_additional_episodes==10000);
assert(s.actor_learning_rate_scale==1 && s.episodes_per_process==s.guard.window);
assert(strcmp(s.expected_runtime_model_sha256,checkpointreview.sha256(fullfile(root,'runtime','FAFA_Simulation.slx'))));
s.expected_runtime_model_sha256=repmat('0',1,64);
file=[tempname '.json'];trainingcurriculum.write_json(file,s);
cleanup=onCleanup(@() delete(file)); %#ok<NASGU>
try
 trainingtools.prepare_recovery_training(fullfile(root,'nonexistent_test_parent'),file);
 error('Test:ExpectedFailure','Mismatched environment accepted.');
catch err
 assert(strcmp(err.identifier,'Recovery:EnvironmentMismatch'));
end
fprintf('PASS pinned model, recovery budget, unchanged LR, early mismatch refusal.\n');
end
