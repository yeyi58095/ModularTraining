# Slower critic pilot frozen outcome

User resumed analysis on2026-10-28 after explicitly pausing it. Read tp230e4814_7dcc_4908_8645_c93b22cbc36c.zip, archived with verified-move SHA/source/destination manifest under artifacts/incoming/sac-mlp-critic-frozen-20261028. No training or runtime modifications. Keep existing meeting/PPT work untouched.

Both evaluations complete, weights_unchanged=true, same child20261027_095822_recovery_tpbc5e6c87, Stage1 seed101 no exploration, same environment/course/engine fingerprints. model.json confirms actor1e-5,critic2e-5,entropy1e-4,replay100k. Packaged status remains guard-paused.

| Checkpoint | Reward | Steps | Original-route max after10s | RMS after10s |
|---|---:|---:|---:|---:|
|2200|2734.7572|3000|6.1824m|3.7235m|
|2500|96.0835|163|50.3589m|35.6468m|

2200 SHA83cfd67b245eb13f6839fc28bd72b74f40aa84cea362387bf946f77cb9490bc8.2500 SHAe7ab1653d536b8629b7df7bdaee86a28af8269d368390d156628f681cbe89996.2500 termination evidence distance_threshold, maximum distance at16.3seconds. Initial50m excluded from after10s comparison.2200 ran to step limit, not proof of full-route completion or generalized robustness.

Prior source2100 frozen reward2839.49,3000steps,max3.4881m/RMS1.8080m after10s. Thus current2200 is usable on the tested route but not a tracking-quality improvement over2100. Runtime storage code changed between old2100 and current evaluation; do not claim all historical software identical. Preserve both, with2100 the better measured reference in this single fixed calm scenario.

worker_attempts.csv exit0,actual workers0(serial),1645.5seconds. Start2026-10-27T01:58:29.3797117Z to02:25:54.8859195Z =09:58:29–10:25:54 Asia/Taipei.414603new steps/1645.5 = approximately251.96steps/s inclusive of startup/save/exit. Run directory09:58:22 is creation time, not start. Previous low-actor-only trial1334.7seconds/290091steps; no isolated speedup attribution to LR/storage/hardware.

Conclusion:119 initial full-length episodes vs82 previously is observed delayed collapse, not durable stabilization.400episode totals differ42.92% in interactions. Failure persists with exploration disabled, so sampled noise alone cannot explain it. Both reduced actor and reduced critic pilots fail to retain skill. Close this rate-reduction pilot; leave guard locked, no direct retry, no further arbitrary LR reduction or thresholds relaxation. No new model corruption evidence. Exact causal learning failure remains unresolved; Q curve observations alone do not establish calibrated overestimation or entropy root cause.

Next decision boundary: retain frozen2100/2200 references, do not request another identical endpoint evaluation or restart identical long training. Further training should follow a separately justified hypothesis/measurement design rather than another numerical LR decrement; this intake does not establish which new recipe would work. No remote command to start training is warranted by these results alone.
