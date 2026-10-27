# MLP saved-state triage

Archive artifacts/incoming/sac-mlp-state-20261027 contains tp70ce3f84_431a_464e_8840_e94af7373143.zip, SHA604197D4BB7230683445ACE946672AB1462E1092E741234EA89F082941653ECE; manifest preserves original/destination and move verified. Three reports complete/source_unchanged,2100/2500 hashes match recovery/frozen reports.2200 SHA47d71d57e3722de495c7743a3c96125b4883564534631b4ad0cc8cc3517c1498.

| Episode | alpha | Critic-target L2 gaps | Recent10000 terminal markers |
|---|---:|---|---:|
|2100|0.00271297|0.11472 /0.09621|4|
|2200|0.00201178|0.24849 /0.21756|21|
|2500|0.00235669|0.27459 /0.24930|78|

All recorded network parameters and sampled replay rewards finite. All actor/critic/entropy optimizer flags and policy state present. Same actor1e-5/critic1e-4/entropy1e-4, gamma.98, batch64, frequency32;100k replay full. Alpha declines then rises while model remains poor; no causal proof that low alpha caused collapse. Alpha is not action std. Parameter gaps are not Q prediction or TD errors; larger gaps cannot establish critic failure. Terminal counts cover recent10000 transitions, not episode failure rate or full replay distribution. Flags alone do not prove every private optimizer field healthy.

Next: probe_sac_mlp_checkpoints on same child's2100/2200/2500, identical two recorded episode prefixes from2100 and2500, at most256 transitions each. Frozen actor Gaussian mean/std and twinQ on recorded actions, no train/sim. Full per-step outputs retained; shared-inputs.mat stored-v7, not models. Avoid loading original HDF5 source by using child's v7 checkpoints. Requires paused/exclusive lock/source hash checks. Existing probe_sac_sequence supports MLP; local paused two-episode fixture passed exit0, weights/source unchanged. Fixture uses one checkpoint and two short source prefixes, not remote long-prefix validation. No claim of TD calibration or causal diagnosis. Keep guard paused; no new training recipe until evidence supports one.
