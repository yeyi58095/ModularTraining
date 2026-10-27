# Slower critic pilot result

Read root10270958stdout.log (not stdout.log), recovery.json, status.json and user training_status attachment. Archived with source/destination SHA manifest and post-move verification under artifacts/incoming/sac-mlp-critic-result-20261027. Run20261027_095822_recovery_tpbc5e6c87, statepaused at2026-10-27 10:25:54+08:00, suspected_regression, no rollback. v7 log, normal save, no crash reported. No live remote state read.

Recovery verifies parent low-actor branch Agent2100 SHA63a549db69ba20f1aef31428cc2bfd5552ea76f859fb3056434afbf346fe1f40; actor remains1e-5, configured critic scale0.2 of1e-4, replay100k, bounded500, v7. Child initial SHA6dc67566af88174bf6b8a07ee17191056c9205b7ca8863f6032cc1222b1166a7. Final runtime options not independently inspected from model.json in this intake; expected critic2e-5 follows validated preparation recipe.

| Episodes | Mean reward | Mean steps | Full3000 count |
|---|---:|---:|---:|
|2101–2200|2760.4196|3000|100|
|2201–2300|478.7899|689.26|19|
|2301–2400|173.3124|299.56|2|
|2401–2500|90.1242|157.21|0|

400unique completed episodes/414603additional steps, final cumulative1999149. First119 episodes2101–2219 full length,2220 drops to155steps; brief recovery2373–2374 then no further full episodes. Guard correctly pauses at2500 before cap2600 after three low windows. Low-actor comparator first82full,2183 firstshort,290091steps. New trial delays firstshort by37episodes but uses42.92% more interaction steps; single-seed/nonidentical stochastic paths and updating distributions do not establish stable superiority or causal repair. Q0about45.94 cannot prove critic correctness. Run creation09:58 is not a verified start timestamp; need worker diagnostics before timing claims.

Decision: retain source and both children paused, no guard bypass or further blind LR reduction. Preserve2200 as candidate, not certified best. Next two separate single-checkpoint no-exploration evaluations2200/2500, same Stage1 seed101 max3000, full traces and model/storage/recovery/guard/status/supervisor/timing packaged. Determine whether2200 preserved physical tracking and whether2500 also fails frozen; no new training until reviewed. No code/runtime changes this turn.
