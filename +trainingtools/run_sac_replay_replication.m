function bundle=run_sac_replay_replication()
% New paired training seed, same frozen diagnostic routes and screening rules.
bundle=trainingtools.run_sac_actor_pilot("replay_replication");
end
