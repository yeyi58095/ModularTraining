# SAC serial restart delivery — 2026-10-21

User chose a fresh serial SAC trial with 500 episodes per attempt after discussing six workers, and authorized local commit/push. Remote original run remains active pending its previously requested graceful pause. No remote connection or training command was executed by the assistant.

## Changes

- Explicit executionMode propagated from retry/control through supervisor/attempt to engine. Default for legacy runs stays parallel; changing execution mode via retry on an existing run is rejected before writing control. New serial runs require SAC, workers=1, minWorkers=1 and no fallback list. The compatibility worker setting does not create a pool; actual pool workers=0.
- Serial path runs the existing model/reset/curriculum/checkpoint/guard logic with UseParallel=false and local model logging preparation. Original stage gates, environment assets, rewards and episode termination are unchanged.
- Default prepare_sac_trial recipe is serial CPU, checkpointEvery=100, episodesPerProcess=500, maxAttempts=1. This is a low-memory comparison, not a demonstrated production speedup or fix for reward collapses.
- New SAC agents preserve InfoToSave.PolicyState, including learned entropy weight. Older snapshots are not rewritten.
- Explicit serial SAC device restoration checks loaded actor/critics, reconstructs through R2024b serialized agent state when needed, and rejects missing optimizer/target/replay/policy-state data. Plain setActor/setCritic would reset important state and are not used as a resume fix. Helper is deliberately limited to R2024b.
- Startup watchdog recognizes serial-ready output. Existing pool/fallback path is unchanged. Supervisor's historical PoolReady column also serves as startup-complete in serial; ActualWorkers=0 is the worker count.

## Validation

- test_sac_learning_frequency_probe: CPU/GPU, frequencies1/8, small synthetic agents; verified serial calls25/4, direct legacy entry32/32. GPU save/load initially restores cpu; restoration returns gpu and preserves serialized optimizer fields, PolicyState, replay length and target weights; subsequent learning succeeds. No claim of all private runtime counters being bitwise identical.
- test_sac_flight('', 'serial'): actual spatial_v2 CPU episodes108/124 steps, two processes/test stages, normal early return and save under a500-episode cap. Actor weights and replay preserved across attempts. Five-step frozen evaluation passed weight-unchanged checks. Source run `20261021_123859_tp09e67cc1_1964_4bae_89fb_5b7e8c43fc9b` is a test run, not a production experiment or convergence result.
- PowerShell parser and test_episode_format passed. Local logs and MAT artifacts remain ignored.
- Final regression process exit=0: test_sac_serial_recipe, test_modular_training, test_curriculum and test_sac_candidate all passed. This covers preparation without launch, rejecting execution-mode changes on an existing run, legacy PPO entry compatibility, curriculum fake-engine wiring, and bounded CPU SAC save/load training.

Observed nonfatal Simulink variant-search/operating-point and modified-model close warnings. Source SLX is not saved by this change. Initial model loading/compilation still costs time; duplicate resume checkpoint loads remain and were not optimized in this patch.

## Important correction

Actual flight stacks use the newer R2024b OffPolicyTrainer, which applies LearningFrequency in parallel too. Earlier analysis of the legacy ExpSyncParallelTrainer does not establish a bug in the currently selected parallel trainer. That attribution was withdrawn explicitly to the user and in current-status/code-review/probe records. Low GPU usage has an independently reproduced save/load-device mechanism; the exact remote runtime device and whole-run timing breakdown still require direct evidence.

## Remote use

Follow [the complete remote guide](../guides/sac-fresh-serial-2026-10-21.md). Do not pull while the old run is active; check paused state and supervisor lock first. Prepare once, retain the new run path receipt, launch that new folder once. No old weights/replay are loaded. At500 episodes the configured one-attempt limit pauses after normal save; this does not mean Stage1 must pass within500 episodes (its minimum remains2000).
