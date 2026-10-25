# SAC shared-input result and bounded actor-rate pilot

## Intake and findings

User supplied tpb965e35a_6163_4efc_8540_e99e014fd5b0.zip. Listed seven expected entries before extraction; moved with original/destination/SHA manifest, verified hash, and extracted under artifacts/incoming/sac-sequence-review-20261025. report-hashes.json includes the small shared-sequences.mat. Five report checkpoint hashes match preceding state diagnostics, source_unchanged and all ten sequence weights_unchanged flags true. Each sequence has256 steps, with summaries after64-step warm-up. Source episodes are3000 steps (100k1600) and450 steps (500k1600), prefixes only.

| Checkpoint | Gaussian std on good prefix | Gaussian std on poor prefix | Twin-Q disagreement on good / poor prefix |
| --- | ---: | ---: | --- |
| Parent1100 | 0.6164 | 0.4129 | 0.0300 / 0.9301 |
| 100k1400 | 0.9404 | 1.0131 | 0.1382 / 0.2283 |
| 100k1600 | 0.09965 | 0.09997 | 0.0783 / 0.1313 |
| 500k1400 | 0.08073 | 0.08417 | 0.0687 / 0.2948 |
| 500k1600 | 0.21467 | 0.20897 | 0.0383 / 0.4595 |

100k1400 mean absolute Gaussian mean on good inputs is1.745 versus0.0841 at1600. The failed500k1600 still has closely agreeing critics on good inputs and Q means45.39/45.36. On poor inputs its Q means34.96/34.50 exceed100k1600's30.01/29.91, but there is no calibrated return/TD target to establish overestimation. Gaussian std is pre-action-transform, not physical actuator std. Parent1100 succeeds despite larger std, so lower std is not a universal criterion. All are off-policy teacher-forced prefixes, not new rollouts or full-buffer samples. These support investigating policy-update stability, not a proven actor-LR cause or exclusion of critic error.

## Chosen pilot

Prepare two new children from baseline100k Agent1600, SHA00dc22b89426dc88a169de5fc5d0a18ae5287e92a686778f4ec4804b4c44c53b. Control actor LR5e-5; candidate actor LR1e-5. Only actor LR changes; critic/entropy settings,100k replay, source learned weights, original course/environment, isDone and gates remain. This numeric factor is a conservative experimental choice, not an inferred optimum. Keep parent and old500k branch paused. Prepare the control now but launch candidate only; comparison will require control later. Episode caps are not matched interaction budgets and cannot prove superiority.

Both new children have serial CPU, fastRestart off, checkpoint every inherited100 episodes,500 episodes/process, maxAttempts1 and500 additional episode recovery budget. Guard thresholds are inherited and not disabled; they may stop earlier. From1600 the upper bound is2100, with original course possibly advancing if its existing conditions are satisfied. No guarantee of stability or overnight duration. Do not lower2000-stage minimum or rewrite old snapshots. Automatic checkpoint-best selection/rollback is not implemented.

R2024b ordinary AgentOptions assignment can reset optimizer state. New set_sac_actor_rate instead edits serialized AgentOptions and value ActorOptimizer.LearnRate together, reconstructs, and verifies actor optimizer equality after restoring just its prior LR for comparison. Critic/entropy optimizer and policy state, network/target weights, chronological replay and IDs are checked unchanged. The preparation helper already clones replay. No change to runtime engine. This relies on inspected R2024b internals, not untested release compatibility.

## Validation

test_sac_actor_rate checks parent in-memory state, exact actor optimizer preservation except LR, disk reload,16 bounded synthetic learning steps after reconstruction, and full child preparation from the existing two-episode flight fixture without launching either child. Source MAT hash, STOP markers, no attempt folders,500 budget, control settings, model validation and saved optimizer rates are checked. Long recurrent training convergence and remote performance are not validated by these tests.

## Remote launch

Keep current runs paused; git pull --ff-only. In MATLAB, verify the known parent checkpoint SHA before preparing. Store the new receipt as artifacts/sac-actor-pair-latest.json and the candidate path as artifacts/sac-actor-pilot-run.txt. Start only candidate with retry(resume=...,maxAttempts=1,fastRestart='off'). This explicit user-executed command launches training; preparation alone does not. Do not rerun preparation unnecessarily: it creates new children.

Monitor training_status(sacDir,50); plot tools/plot_training_rewards.py using the new pilot receipt, not the old serial receipt. maxAttempts1 makes the attempt end normally without starting another segment; the recovery budget also caps added episodes. Do not create STOP for a normal segment-end pause: supervisor STOP terminates an active attempt and only preserves already completed checkpoints. After completion, retain logs and frozen-evaluate the new checkpoints before any further run.
