# SAC replay pilot and curriculum recommendation

## Evidence and intake

User supplied1025stdout.log and a training_status paste. Candidate20261023_204044_recovery_tp6038f3af reports normal save through1600 and paused at2026-10-25T02:30:27+08:00 due maximum attempts; success0, Stage1 straight_calm. Exactly500 unique logged episodes1101–1600,1053075 new steps. Baseline consumed750422 steps for the same500-episode cap: candidate uses40.33% more interactions, so this is not an equal-step causal comparison. Duration not provided. Single continuation per capacity; random training streams not proven paired.

| Window | Candidate reward | Mean steps | Full episodes/100 |
| --- | ---: | ---: | ---: |
| 1101–1200 | 2515.41 | 2788.11 | 90 |
| 1201–1300 | 2170.24 | 2347.25 | 66 |
| 1301–1400 | 2837.76 | 3000 | 100 |
| 1401–1500 | 2107.19 | 2267.56 | 71 |
| 1501–1600 | 76.55 | 127.83 | 0 |

Baseline latest100 reward927.11/full32%, candidate76.55/full0%. Candidate had a long successful period but still collapsed. This does not establish larger capacity universally worse, nor prove buffer replacement is the cause. Final5 steps162/161/152/191/450; footer last50 mean73.7736. Both remain paused; no new training recommended before frozen comparison.

Seven root intake files moved with prewritten manifest and verified SHA256 into artifacts/incoming/root-intake-20261025: candidate log under sac-buffer500k; old parallel attempt1/2/3 logs and historical2026-10-21 status.json under sac-old-parallel; stdout_new.log and reward_history.csv under sac-serial-parent. Root had no PNG files. User's current screenshot/status attachment were copied under sac-buffer500k; original attachments retained. No tracked source/config, run directory, ZIP or unrelated presentation moved. Old root status.json is a historical uploaded artifact, not a live local run control.

## Curriculum assessment

Current repository SAC and PPO course diff consists of model identity and two asset paths resolving the same routes. Stage order, wind, thresholds and budgets otherwise match. Therefore the user is right that the course was inherited. This does not make the task inherently PPO-only. All observed regressions occurred inside Stage1, before a stage transition. Blaming later-course difficulty or solving this by relaxing gates is unsupported.

Recommend a separate, versioned SAC training/evaluation protocol, initially with the same task and validation standards. Proposed, not implemented:

1. Account for environment steps, update counts and wall time, rather than using episode count alone as sample budget. Keep500 episodes as a process ceiling, not the experimental unit.
2. Evaluate frozen policies periodically both deterministically and with original exploration, distinguishing training reward from held-out performance. Gate on survival and original-route deviation, not only averaged reward. Exact new thresholds require explicit design and a new course version; do not alter snapshots.
3. Record entropy coefficient, critic/actor losses, action std/saturation and replay composition. These are not available in current logs; do not claim automatic corrective control.
4. Once Stage1 stability is understood, test gradual changes in initial conditions, route curvature and wind, and plan replay composition around transitions. Keep the same observation/action/reward semantics within each interpretable comparison, retaining earlier-stage evaluations. Never mix unobserved task identities with incompatible rewards in replay.
5. Preserve original isDone and standard acceptance. Merely lowering2000 minimum episodes to let an unstable high-reward period advance does not repair the policy.

References inspected2026-10-25: [MathWorks SAC](https://www.mathworks.com/help/reinforcement-learning/ug/soft-actor-critic-agents.html) describes off-policy replay/twin critics; [Spinning Up SAC](https://spinningup.openai.com/en/latest/algorithms/sac.html) separates stochastic training from deterministic test returns. These support separate evaluation and replay-aware design, not a validated numeric flight recipe. Current MathWorks docs cover newer features; no unsupported new option introduced into R2024b.

Next user-executed diagnostic: frozen Stage1 comparisons for both branches at1400 and1600, seeds101/102/103, with and without exploration,24 simulations capped3000 steps. This is same-task checkpoint quality evidence, not multi-route robustness or equal-training-budget superiority. Do not resume either training branch or rebuild a curriculum yet.
