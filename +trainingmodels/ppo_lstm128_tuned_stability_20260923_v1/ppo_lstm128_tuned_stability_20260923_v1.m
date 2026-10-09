function spec = ppo_lstm128_tuned_stability_20260923_v1()
% Data-informed stability trial, NOT a validated performance improvement.
% Baseline logs: 20260922_122929_tp02dc5edf_2a72_40db_9688_ae5cdbc2383e.
% Late reward/episode-length regression motivates smaller policy updates.
% See TUNING.md and evidence.json beside this file for evidence and limitations.
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_lstm128_tuned_stability_20260923_v1';
spec.actorLearnRate = 2.5e-5; % Baseline 5e-5: halve the actor learning rate.
spec.numEpoch = 2;          % Baseline 3: fewer passes over each experience batch.
end
