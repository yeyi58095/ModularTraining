# SAC parameter and reward review — 2026-10-22

## Evidence

User-provided root reward_history.csv SHA256: 05864D9AD13CA3A265B3D10E0CFAEF927C8EC05A2F96BD2DD3D7C0C086E67073. Exactly 1905 unique, consecutive episodes 1–1905, all source_run=20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b. Attempts 1/2/3 contain 500 rows each; attempt4 contains 405. Sum of steps=1554318. CSV has no timestamps, entropy coefficient, losses, stage or environment hashes; remote current state and runtime parameter values were not independently inspected.

| Episodes | Mean reward | Mean steps | Full 3000-step rate |
| --- | ---: | ---: | ---: |
| 1001–1100 | 2688.33 | 3000.00 | 100% |
| 1101–1200 | 1728.51 | 1952.34 | 58% |
| 1201–1300 | 2578.26 | 2861.27 | 94% |
| 1301–1400 | 553.60 | 696.33 | 19% |
| 1401–1500 | 56.57 | 97.61 | 0% |
| 1501–1600 | 56.65 | 96.91 | 0% |
| 1601–1700 | 131.31 | 186.30 | 0% |
| 1701–1800 | 1069.84 | 1230.11 | 27% |
| 1801–1900 | 1703.42 | 1928.24 | 56% |
| 1806–1905 (latest100) | 1707.45 | 1928.24 | 56% |

Collapse begins inside attempt3: episodes1313–1319 still last3000 steps while reward decreases2742.59→1459.49, episode1320 lasts2567, episode1321 lasts165. Thus not simply a restart boundary, and reward degradation precedes termination. Stage1 minimum2000 under the previously confirmed course makes a normal stage transition before1905 inconsistent with that course; the CSV alone cannot certify stage snapshots. Q0 remains about38 during collapse: a diagnostic observation, not proof of critic overestimation (Q0 is a discounted soft value, not undiscounted episode return).

## Repository recipe versus external references

Current repository sac_lstm128/build_sac: LSTM128, gamma0.98, actor LR5e-5, critic LR1e-4, entropy LR1e-4, initial alpha0.1 with automatic target entropy -1, tau0.005, buffer100000, minibatch64 sequences of length32, warm start1000, LearningFrequency32, MaxMiniBatchPerEpoch1, NumEpoch1. These are source settings, not a fresh inspection of the remote saved agent.

- [SB3 v2.3.0 SAC](https://stable-baselines3.readthedocs.io/en/v2.3.0/modules/sac.html): LR3e-4, batch256, buffer1e6, gamma0.99, tau0.005, automatic entropy, train_freq1/gradient_steps1. Feedforward comparison, not a recurrent flight prescription.
- [Spinning Up SAC](https://spinningup.openai.com/en/latest/algorithms/sac.html): LR1e-3, batch100, replay1e6, gamma0.99, polyak0.995 (tau0.005), fixed alpha0.2. [Implementation](https://spinningup.openai.com/en/latest/_modules/spinup/algos/pytorch/sac/sac.html) runs50 updates after50 collected steps; update_every50 does not mean one update per50 steps.
- [RL Zoo SAC recipes](https://github.com/DLR-RM/rl-baselines3-zoo/blob/master/hyperparams/sac.yml), inspected2026-10-22: tuned MountainCar uses train_freq32/gradient_steps32, buffer50000, batch512, gamma0.9999, fixed entropy0.1; tuned BipedalWalker uses64/64, buffer300000, batch256, gamma0.98, automatic entropy. These task-specific MLP/SDE settings illustrate variation, not transferable validated flight settings.
- [MathWorks option semantics](https://www.mathworks.com/help/reinforcement-learning/ref/rl.option.rlsacagentoptions.html): recurrent batches contain sequences; LearningFrequency and maximum minibatches must be considered together. Online page currently identifies R2026b. Local R2024b rlSACAgentOptions and OffPolicyTrainer were separately read to verify the relevant properties and serial trainer path; no new release-only option is proposed.

## Interpretation and proposed order (not applied)

This is sustained performance loss and recovery, not merely a few noisy episodes. Lowering LR blindly is not supported: current rates are already below the reference defaults. A100000-transition buffer holds only about33.3 full3000-step episodes; rapid replacement is a testable hypothesis, not established catastrophic forgetting. Current serial schedule allows roughly one minibatch update per32 new steps after warmup; 64x32 sequence positions cannot be equated with independent feedforward samples or with32 optimizer updates. Increasing update intensity costs time and may destabilize training, so do not jump to1:1 by copying SB3.

First compare available frozen checkpoints around1100/1300/1500/1900 using identical routes/seeds and both exploration settings, and inspect alpha, action saturation/std, critic/actor losses and update counts if available. Distinguish exploration-induced failures from degraded deterministic policy. Do not change reward/isDone/course gates. No inference that Fast Restart caused or repaired collapse.

Candidate controlled child-run experiments, after normal pause and explicit implementation: (A) buffer100000→500000 alone, retaining available history (lost history cannot be recovered merely by increasing capacity); (B) LearningFrequency32→8 alone with max minibatches1; compare equal environment steps, wall time and paired frozen evaluations. Keep LR, gamma, entropy target, sequence/batch sizes unchanged initially. These are proposed ablations, not proven fixes. Consider entropy-target changes only after exploration diagnostics; a lower target encourages lower entropy. Use multiple seeds for any claim of robust improvement.

No runtime edits, training start/stop, remote connection, or source CSV modifications in this review. Analysis used numeric rows and independently checked counts/source identifiers; only this summary is committed.
