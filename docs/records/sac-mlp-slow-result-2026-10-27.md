# Low actor rate MLP result

Read full0152stdout.log and user training_status attachment. Run20261027_015231_recovery_tpbbe84468, starts from2100, serialCPU, explicit-v7 storage.400 unique completed episodes2101–2500,290091 additional steps. First82 episodes2101–2182 all3000 steps;2183 drops to162 steps/reward85.85. No later full-length episode. No native crash recorded in this attempt; normal save/guard stop at2500, suspected_regression, status paused at2026-10-27 08:53:11+08:00. This does not prove native crashes globally fixed.

| Window | Mean reward | Mean steps | Full3000 |
|---|---:|---:|---:|
|2101–2200|2215.1471|2487.24|82%|
|2201–2300|77.5169|138.89|0%|
|2301–2400|79.8363|144.09|0%|
|2401–2500|75.2545|130.69|0%|

Three consecutive low100-episode windows explain guard stop before2600. Training instability remains with actor1e-5; not proof actor LR caused it or lower rate is universally worse. Old parent branch differs in seed/update trajectory and storage, so not a controlled superiority claim. Episode Q0 around46 does not independently prove value overestimation. No full attempt duration available in stdout; request supervisor/worker diagnostics before reporting throughput. Training return is not a frozen checkpoint result.

Next: keep guard lock and parent unchanged; no retry or further blind LR/curriculum changes. One seed101 Stage1 frozen no-exploration evaluation of this child Agent2500,3000 maxsteps. Bundle full evaluation folder, recovery/model/storage/guard/status/control JSON plus supervisor.log and worker_attempts.csv. This tests whether sampled exploration alone explains training collapse; not multi-seed certification. Prior parent2100 report already available; do not rerun it.

Inputs archived with source/destination SHA manifest and post-move verification at artifacts/incoming/sac-mlp-slow-result-20261027. sac-actor-pair-latest.json is still old recurrent pair from20261025, not newMLP provenance. Status attachment copied to training-status.txt. No runtime/config changes or training started this turn.

Correct serial launch parameter remains fallbackWorkers=[]; earlier suggested1 was rejected before launch and corrected. Never repeat preparation solely to address that argument error.
