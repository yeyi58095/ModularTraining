function bundle=run_sac_replay_retention()
% Explicit bounded training entry: two independently forked 100-episode arms.
bundle=trainingtools.run_sac_actor_pilot("replay_retention");
end
