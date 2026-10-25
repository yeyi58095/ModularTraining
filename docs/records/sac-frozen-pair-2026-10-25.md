# SAC replay pair: frozen checkpoint evaluation

## Evidence

Received `tp603c8c0e_0d03_4fea_880b_06b261481af5.rar` from the project root. Listed archive entries before extraction: four JSON reports and their containing directory. Moved archive to `artifacts/incoming/sac-frozen-pair-20261025`, recorded original/destination paths and SHA256 in intake-manifest.json, verified hash after move. Extracted reports and copied user terminal output there; report-hashes.json records individual JSON hashes. Embedded remote paths remain unchanged.

All four reports are complete, weights_unchanged=true, R2024b CPU, Stage1 straight_calm, seeds101/102/103, max3000 steps, exploration scale1. Each contains six results (24 total). Environment spatial_v2; model, curriculum, runtime and route hashes agree across reports. Checkpoint hashes agree between exploration modes within each branch. These are reported evaluation provenance, not independent access to remote MAT files.

Baseline100k: 20261023_203402_recovery_tp85477afc. Candidate500k: 20261023_204044_recovery_tp6038f3af.

| Buffer/checkpoint | Deterministic steps | Exploration steps (101/102/103) | Deterministic reward | Max finite-route distance after10s, deterministic / exploration |
| --- | ---: | --- | ---: | --- |
| 100k/1400 | 85 | 85/88/85 | 48.73 | unavailable: all terminate before10s |
| 100k/1600 | 3000 | 3000/3000/3000 | 3109.59 | 0.984m / 1.120–1.381m |
| 500k/1400 | 3000 | 3000/3000/3000 | 3070.12 | 2.252m / 2.187–2.389m |
| 500k/1600 | 208 | 219/195/214 | 149.86 | 50.015m / 50.191–50.275m |

Deterministic results repeat identically across the three seeds on this fixed calm route; these are not three independent routes. Successful policies have all-sample maximum50m from initialization, which must not be confused with later deviation. Failed evaluations all report distance_threshold terminal observation evidence, not instrumented internal IsDone branch attribution. 100k/1400 exploration action saturation is1.14–3.53%; all other evaluations report zero saturation. No measured training/whole-evaluation duration inferred from directory timestamps.

## Interpretation and decision

Both capacities exhibit changing checkpoint quality:100k recovers by1600 after failing at1400;500k deteriorates from1400 to1600. Disabling exploration does not rescue failed checkpoints. Expanding replay did not eliminate instability in this pilot. Different interaction budgets (750422 vs1053075 new steps) and single continuations prevent causal or universal capacity rankings.

100k/1600 is a useful preserved reference for this Stage1 scenario, with smaller late route deviation than500k/1400. Neither establishes long-term training stability, course completion, or generalization. A low rolling training average can coexist with a good final policy after recovery; it describes earlier changing policies, not just the frozen final agent.

Keep both runs paused and preserve original checkpoints. Do not restart500k/1600, overwrite snapshots, lower promotion gates or launch a new curriculum as a purported fix. The case for a separate SAC protocol is stronger for checkpoint evaluation and retention, but these within-Stage1 failures still do not identify curriculum as the cause. Next development priority is bounded checkpoint diagnostics (entropy coefficient, actor/critic/target state and update/replay statistics where available), then a single-factor child experiment with matched interaction budgets. Current JSON reports lack loss/entropy histories, so no learning-rate or entropy root cause is established. No runtime change or training launched in this review.
