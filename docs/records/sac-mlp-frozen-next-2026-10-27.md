# MLP frozen comparison and bounded continuation

Input ZIP tp43f5f64b_f55e_4284_911b_360ba1617b05.zip archived with verified SHA256 F9F80AD65BFCE1B015616EB76197185366A5A490DCD6F5ADA62928A8A6A5B2C2 under artifacts/incoming/sac-mlp-frozen-comparison-20261027. Original/destination paths are recorded in intake-manifest.json; extracted reports retain remote paths. Three reports are complete, weights_unchanged=true, same session/model/environment/course/runtime fingerprints, Stage1 seed101 with exploration disabled. Packaged status is paused at2500. This is received evidence, not live remote observation.

| Checkpoint | Reward | Steps | Original finite route max after10s | RMS after10s |
|---|---:|---:|---:|---:|
|2100|2839.49|3000|3.488m|1.808m|
|2300|69.11|120|50.065m|42.523m|
|2500|2283.80|3000|17.945m|13.655m|

2300 terminates with distance_threshold evidence even without exploration; noise alone does not explain this trough. 2500 recovers episode length but has worse tracking than2100. Initial50m distance is excluded from after10s comparisons; 3000steps is not full route completion. One fixed calm route with one seed is not generalization or multi-seed certification. No exploration-on results received. Crash root cause remains unknown.

Selected source2100 SHA256: 03bb547cb232810fec17566e535808219247d4f1ff680430bed6c42421df06e1. Source run: experiments/sac_mlp_stage1_v1/runs/20261026_203618_recovery_tp18ecff57. Keep source paused and preserve2500. Prepare an independent child with configs/sac_mlp_2100_actor_slow.json: actor5e-5 to1e-5, unchanged100k replay, critic/entropy settings, model and environment. Actor rate factor0.2 is an experimental choice, not proven optimum or established root-cause repair. Prior recurrent low-rate result is not proof for MLP. No fresh random restart or relaxed success conditions.

Operational protection changes are explicit: this child is not continuous_training; new guard enables500 additional episode budget and regression_action=pause,100-window/patience3 with existing ratios. Parent continuous course snapshot has on_limit=continue and is inherited unchanged, so the guard is the additional-budget cap. Existing course gates can complete earlier; guard can pause earlier. Run serialCPU,fastRestart off,checkpoint100,episodesPerProcess500,maxAttempts1,maxNoProgressFailures1. Maximum endpoint2600, not guaranteed500 or guaranteed duration. No automatic rollback. Do not delete guard state or restart indefinitely.

Validation: test_sac_mlp_slow_preparation passed on local R2024b using existing two-episode MLP flight fixture. Helper prepared child with preserved source SHA and weights,1e-5 serialized actor optimizer, budget/pause rules, STOP marker and no attempts; disk reload/model validation passed. No train/sim launched. Fixture is stage2 and episode2, not the remote stage1/2100; remote exact source SHA and model/LR checks are required. Existing helper performs optimizer/replay preservation checks; no runtime modifications this turn.

Remote sequence: git pull --ff-only; read sac-mlp-continuous-100k-run.txt and verify exact source name, paused, sac_mlp128 and source checkpoint SHA. Call prepare_recovery_training(source,fullfile(pwd,'configs','sac_mlp_2100_actor_slow.json')), save child path to artifacts/sac-mlp-slow-actor-run.txt, then explicit retry with above limits. Source remains paused. Monitor training_status(sacDir,50); plot tools/plot_training_rewards.py with this new receipt. Finish with stdout, recovery.json, status, diagnostics timing and frozen evaluation; training reward alone cannot establish stability. Remote preparation/training not executed by agent.
