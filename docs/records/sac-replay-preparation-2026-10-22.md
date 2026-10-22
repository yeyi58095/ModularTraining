# SAC replay-only child preparation

User authorized continuing through a concrete remote instruction and recording this preference in AGENTS.md. No MATLAB process was reported by the initial local process check before implementation; subsequent processes are the explicitly bounded tests in this task. No remote connection or training launch.

## Implementation

R2024b rlSACAgent.setAgentOptions_ resets optimizer/algorithm state on option changes. Therefore direct capacity assignment is unsuitable for a one-factor experiment. trainingtools.resize_sac_replay reconstructs saveobj/loadobj state, copies replay before resizing, and verifies replay contents, actor/twin-critic/target weights, actor/critic/entropy optimizer states and policy state. Only growth or unchanged capacity is allowed, and support is restricted to R2024b.

prepare_recovery_training now permits SAC only for bounded replay-capacity changes with actor LR scale1, unchanged exploration and no continuous-training mode. Existing PPO behavior remains. Parent checkpoint, course/environment, model source, history, lineage and SHA protections are retained. The child model spec records its capacity. The helper does not convert PPO into SAC.

prepare_sac_replay_pair prepares two independent children from the same chosen checkpoint, verifies matching parent checkpoint/course/model SHA, and emits a unique pair.json receipt. Baseline100000, candidate500000; serial CPU,500 episodes/attempt, maxAttempts1,1000-additional-episode safety budget. Original guard thresholds inherited where present, otherwise existing recovery defaults; course is not relaxed. STOP remains present until an explicit future start. Neither child starts during preparation. This is not yet an equal-environment-step training controller, so equal episode counts must not be claimed as equal sample budgets.

## Verification

test_sac_replay_resize passed with a16-unit recurrent synthetic agent:32 steps before resize and32 after reload. Optimizer/entropy state checks, replay contents, original-agent replay isolation, disk reload and further actor learning passed. This is not a flight-performance or convergence benchmark.

test_sac_replay_pair passed using the existing saved2-episode serial flight fixture: child100k/500k capacities, history, schema validation, parent-file SHA preservation, STOP and no attempt directories verified. The fixture is a small test run, not the remote1100 checkpoint. Remote preparation reruns the state-preservation assertions against the actual saved checkpoint; RAM/disk requirements there remain unmeasured.

Remote steps are in docs/guides/sac-replay-pair-2026-10-22.md. Next action is preparation and receipt review, not restarting the original run or launching both branches. Raw test outputs remain ignored.

Final regression batch exited0: updated test_sac_replay_pair (including parent SHA matching) and test_long_recovery (existing PPO500/1000-episode preparation) both passed. The remote PowerShell block passes AST parsing and git diff --check passed.
